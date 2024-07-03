#!/usr/bin/env bash

#############
# Validations
#############
PR_NUMBER=$(jq -r ".pull_request.number" "$GITHUB_EVENT_PATH")
if [[ "$PR_NUMBER" == "null" ]]; then
	echo "This isn't a PR."
	exit 0
fi

if [[ -z "$GITHUB_TOKEN" ]]; then
	echo "GITHUB_TOKEN environment variable missing."
	exit 1
fi

if [[ ! "$1" =~ ^(fmt|init|plan|validate)$ ]]; then
  echo -e "Unsupported command \"$1\". Valid commands are \"fmt\", \"init\", \"plan\", \"validate\"."
  exit 1
fi

if [[ ! -f $2 ]]; then
  echo "The provided file does not exist."
  exit 1
fi

if [[ -z $3 ]]; then
  echo "There must be an exit code from a previous step."
  exit 1
fi

##################
# Shared Variables
##################
# Arg 1 is command
COMMAND=$1
# Arg 2 is input file. We strip ANSI colours.
INPUT=$(cat "/github/workspace/$2" | sed 's/\x1b\[[0-9;]*m//g')
# Arg 3 is the Terraform CLI exit code
EXIT_CODE=$3
# Arg 4 is the Job name
JOB_NAME=$4
# Arg 5 is the Step name
STEP_NAME=$5

# The char limit for comments is 65535. Leave space for comment wrapper (max 535 chars)
COMMENT_CHAR_LIMIT=65000 


# Read TF_WORKSPACE environment variable or use "default"
WORKSPACE=${TF_WORKSPACE:-default}

# Read EXPAND_SUMMARY_DETAILS environment variable or use "true"
if [[ ${EXPAND_SUMMARY_DETAILS:-true} == "true" ]]; then
  DETAILS_STATE=" open"
else
  DETAILS_STATE=""
fi

# Read HIGHLIGHT_CHANGES environment variable or use "true"
COLOURISE=${HIGHLIGHT_CHANGES:-true}

ACCEPT_HEADER="Accept: application/vnd.github.v3+json"
AUTH_HEADER="Authorization: token $GITHUB_TOKEN"
CONTENT_HEADER="Content-Type: application/json"

PR_COMMENTS_URL=$(jq -r ".pull_request.comments_url" "$GITHUB_EVENT_PATH")
PR_COMMENT_URI=$(jq -r ".repository.issue_comment_url" "$GITHUB_EVENT_PATH" | sed "s|{/number}||g")

# Generate Terraform run logs URL
LOGS_URL=$GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID
if [[ -n "$JOB_NAME" ]]; then
  jobs_url="https://api.github.com/repos/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID/jobs"
  jobs_json=$(curl -sS -H "$AUTH_HEADER" -H "$ACCEPT_HEADER" -H "$CONTENT_HEADER" -L $jobs_url)
  job_json=$(echo "$jobs_json" | jq --arg job_name "$JOB_NAME" -r '.jobs[] | select(.name == $job_name and .status == "in_progress")')
  job_id=$(echo "$job_json" | jq -r '.id')
  if [[ -n "$job_id" ]]; then
    LOGS_URL="$LOGS_URL/job/$job_id"
  fi

  if [[ -n "$STEP_NAME" ]]; then
    step_id=$(echo "$job_json" | jq --arg step_name "$STEP_NAME" -r '.steps[] | select(.name == $step_name) | .number')
    if [[ -n "$step_id" ]]; then
      LOGS_URL="$LOGS_URL#step:$step_id:1"
    fi
  fi
fi


##############
# Handler: fmt
##############
if [[ $COMMAND == 'fmt' ]]; then
  # Look for an existing fmt PR comment and delete
  echo -e "\033[34;1mINFO:\033[0m Looking for an existing fmt PR comment."
  PR_COMMENT_ID=$(curl -sS -H "$AUTH_HEADER" -H "$ACCEPT_HEADER" -L "$PR_COMMENTS_URL" | jq '.[] | select(.body|test ("### Terraform `fmt` Failed")) | .id')
  if [ "$PR_COMMENT_ID" ]; then
    echo -e "\033[34;1mINFO:\033[0m Found existing fmt PR comment: $PR_COMMENT_ID. Deleting."
    PR_COMMENT_URL="$PR_COMMENT_URI/$PR_COMMENT_ID"
    curl -sS -X DELETE -H "$AUTH_HEADER" -H "$ACCEPT_HEADER" -L "$PR_COMMENT_URL" > /dev/null
  else
    echo -e "\033[34;1mINFO:\033[0m No existing fmt PR comment found."
  fi

  # Exit Code: 0
  # Meaning: All files formatted correctly.
  # Actions: Exit.
  if [[ $EXIT_CODE -eq 0 ]]; then
    echo -e "\033[34;1mINFO:\033[0m Terraform fmt completed with no errors. Continuing."

    exit 0
  fi

  # Exit Code: 1, 2
  # Meaning: 1 = Malformed Terraform CLI command. 2 = Terraform parse error.
  # Actions: Build PR comment.
  if [[ $EXIT_CODE -eq 1 || $EXIT_CODE -eq 2 ]]; then
    PR_COMMENT="### Terraform \`fmt\` Failed
<details$DETAILS_STATE><summary>Show Output</summary>

\`\`\`
$INPUT
\`\`\`
</details>

Please visit [logs]($LOGS_URL) for a full, detailed output.
"
  fi

  # Exit Code: 3
  # Meaning: One or more files are incorrectly formatted.
  # Actions: Iterate over all files and build diff-based PR comment.
  if [[ $EXIT_CODE -eq 3 ]]; then
    ALL_FILES_DIFF=""
    for file in $INPUT; do
      THIS_FILE_DIFF=$(terraform fmt -no-color -write=false -diff "$file")
      ALL_FILES_DIFF="$ALL_FILES_DIFF
<details$DETAILS_STATE><summary><code>$file</code></summary>

\`\`\`diff
$THIS_FILE_DIFF
\`\`\`
</details>"
    done

    PR_COMMENT="### Terraform \`fmt\` Failed
$ALL_FILES_DIFF

Please visit [logs]($LOGS_URL) for a full, detailed output.
"
  fi

  # Add fmt failure comment to PR.
  PR_PAYLOAD=$(echo '{}' | jq --arg body "$PR_COMMENT" '.body = $body')
  echo -e "\033[34;1mINFO:\033[0m Adding fmt failure comment to PR."
  curl -sS -X POST -H "$AUTH_HEADER" -H "$ACCEPT_HEADER" -H "$CONTENT_HEADER" -d "$PR_PAYLOAD" -L "$PR_COMMENTS_URL" > /dev/null

  exit 0
fi

###############
# Handler: init
###############
if [[ $COMMAND == 'init' ]]; then
  # Look for an existing init PR comment and delete
  echo -e "\033[34;1mINFO:\033[0m Looking for an existing init PR comment."
  PR_COMMENT_ID=$(curl -sS -H "$AUTH_HEADER" -H "$ACCEPT_HEADER" -L "$PR_COMMENTS_URL" | jq '.[] | select(.body|test ("### Terraform `init` Failed")) | .id')
  if [ "$PR_COMMENT_ID" ]; then
    echo -e "\033[34;1mINFO:\033[0m Found existing init PR comment: $PR_COMMENT_ID. Deleting."
    PR_COMMENT_URL="$PR_COMMENT_URI/$PR_COMMENT_ID"
    curl -sS -X DELETE -H "$AUTH_HEADER" -H "$ACCEPT_HEADER" -L "$PR_COMMENT_URL" > /dev/null
  else
    echo -e "\033[34;1mINFO:\033[0m No existing init PR comment found."
  fi

  # Exit Code: 0
  # Meaning: Terraform successfully initialized.
  # Actions: Exit.
  if [[ $EXIT_CODE -eq 0 ]]; then
    echo -e "\033[34;1mINFO:\033[0m Terraform init completed with no errors. Continuing."

    exit 0
  fi

  # Exit Code: 1
  # Meaning: Terraform initialize failed or malformed Terraform CLI command.
  # Actions: Build PR comment.
  if [[ $EXIT_CODE -eq 1 ]]; then
    PR_COMMENT="### Terraform \`init\` Failed
<details$DETAILS_STATE><summary>Show Output</summary>

\`\`\`
$INPUT
\`\`\`
</details>

Please visit [logs]($LOGS_URL) for a full, detailed output.
"
  fi

  # Add init failure comment to PR.
  PR_PAYLOAD=$(echo '{}' | jq --arg body "$PR_COMMENT" '.body = $body')
  echo -e "\033[34;1mINFO:\033[0m Adding init failure comment to PR."
  curl -sS -X POST -H "$AUTH_HEADER" -H "$ACCEPT_HEADER" -H "$CONTENT_HEADER" -d "$PR_PAYLOAD" -L "$PR_COMMENTS_URL" > /dev/null

  exit 0
fi

###############
# Handler: plan
###############
if [[ $COMMAND == 'plan' ]]; then
  # Look for an existing plan PR comment and delete
  echo -e "\033[34;1mINFO:\033[0m Looking for an existing plan PR comment."
  PR_COMMENT_ID=$(curl -sS -H "$AUTH_HEADER" -H "$ACCEPT_HEADER" -L "$PR_COMMENTS_URL" | jq '.[] | select(.body|test ("### Terraform `plan` .* for Workspace: `'"$WORKSPACE"'`")) | .id')
  if [ "$PR_COMMENT_ID" ]; then
    echo -e "\033[34;1mINFO:\033[0m Found existing plan PR comment: $PR_COMMENT_ID. Deleting."
    PR_COMMENT_URL="$PR_COMMENT_URI/$PR_COMMENT_ID"
    curl -sS -X DELETE -H "$AUTH_HEADER" -H "$ACCEPT_HEADER" -L "$PR_COMMENT_URL" > /dev/null
  else
    echo -e "\033[34;1mINFO:\033[0m No existing plan PR comment found."
  fi

  # Exit Code: 0, 2
  # Meaning: 0 = Terraform plan succeeded with no changes. 2 = Terraform plan succeeded with changes.
  # Actions: Strip out the refresh section, ignore everything after the 72 dashes, format, colourise and build PR comment.
  if [[ $EXIT_CODE -eq 0 || $EXIT_CODE -eq 2 ]]; then
    CLEAN_PLAN=$(echo "$INPUT" | sed -r '/^(An execution plan has been generated and is shown below.|Terraform used the selected providers to generate the following execution|No changes. Infrastructure is up-to-date.|No changes. Your infrastructure matches the configuration.|Note: Objects have changed outside of Terraform)$/,$!d') # Strip refresh section
    
    if [[ ${#CLEAN_PLAN} -gt $COMMENT_CHAR_LIMIT ]]; then
      CLEAN_PLAN="...TRUNCATED...\n\n${CLEAN_PLAN:${#CLEAN_PLAN}-COMMENT_CHAR_LIMIT:COMMENT_CHAR_LIMIT}" # Truncate plan to COMMENT_CHAR_LIMIT (from the beginning)
    fi

    CLEAN_PLAN=$(echo "$CLEAN_PLAN" | sed -r 's/^([[:blank:]]*)([-+~])/\2\1/g') # Move any diff characters to start of line

    if [[ $COLOURISE == 'true' ]]; then
      CLEAN_PLAN=$(echo "$CLEAN_PLAN" | sed -r 's/^~/!/g') # Replace ~ with ! to colourise the diff in GitHub comments
    fi
    PR_COMMENT="### Terraform \`plan\` ✅**SUCCEEDED**✅ for Workspace: \`$WORKSPACE\`
<details$DETAILS_STATE><summary>Show Output</summary>

\`\`\`diff
$CLEAN_PLAN
\`\`\`
</details>

Please visit [logs]($LOGS_URL) for a full, detailed output.
"
  fi

  # Exit Code: 1
  # Meaning: Terraform plan failed.
  # Actions: Build PR comment.
  if [[ $EXIT_CODE -eq 1 ]]; then
    if [[ ${#INPUT} -gt $COMMENT_CHAR_LIMIT ]]; then
      CLEAN_INPUT="...TRUNCATED...\n\n${INPUT:${#INPUT}-COMMENT_CHAR_LIMIT:COMMENT_CHAR_LIMIT}" # Truncate input to COMMENT_CHAR_LIMIT (from the beginning)
    fi

    PR_COMMENT="### Terraform \`plan\` ❌**FAILED**❌ for Workspace: \`$WORKSPACE\`
<details$DETAILS_STATE><summary>Show Output</summary>

\`\`\`
$CLEAN_INPUT
\`\`\`
</details>

Please visit [logs]($LOGS_URL) for a full, detailed output.
"
  fi

  # Add plan comment to PR.
  PR_PAYLOAD=$(echo '{}' | jq --arg body "$PR_COMMENT" '.body = $body')
  echo -e "\033[34;1mINFO:\033[0m Adding plan comment to PR."
  curl -sS -X POST -H "$AUTH_HEADER" -H "$ACCEPT_HEADER" -H "$CONTENT_HEADER" -d "$PR_PAYLOAD" -L "$PR_COMMENTS_URL" > /dev/null

  exit 0
fi

###################
# Handler: validate
###################
if [[ $COMMAND == 'validate' ]]; then
  # Look for an existing validate PR comment and delete
  echo -e "\033[34;1mINFO:\033[0m Looking for an existing validate PR comment."
  PR_COMMENT_ID=$(curl -sS -H "$AUTH_HEADER" -H "$ACCEPT_HEADER" -L "$PR_COMMENTS_URL" | jq '.[] | select(.body|test ("### Terraform `validate` Failed")) | .id')
  if [ "$PR_COMMENT_ID" ]; then
    echo -e "\033[34;1mINFO:\033[0m Found existing validate PR comment: $PR_COMMENT_ID. Deleting."
    PR_COMMENT_URL="$PR_COMMENT_URI/$PR_COMMENT_ID"
    curl -sS -X DELETE -H "$AUTH_HEADER" -H "$ACCEPT_HEADER" -L "$PR_COMMENT_URL" > /dev/null
  else
    echo -e "\033[34;1mINFO:\033[0m No existing validate PR comment found."
  fi

  # Exit Code: 0
  # Meaning: Terraform successfully validated.
  # Actions: Exit.
  if [[ $EXIT_CODE -eq 0 ]]; then
    echo -e "\033[34;1mINFO:\033[0m Terraform validate completed with no errors. Continuing."

    exit 0
  fi

  # Exit Code: 1
  # Meaning: Terraform validate failed or malformed Terraform CLI command.
  # Actions: Build PR comment.
  if [[ $EXIT_CODE -eq 1 ]]; then
    PR_COMMENT="### Terraform \`validate\` Failed
<details$DETAILS_STATE><summary>Show Output</summary>

\`\`\`
$INPUT
\`\`\`
</details>

Please visit [logs]($LOGS_URL) for a full, detailed output.
"
  fi

  # Add validate failure comment to PR.
  PR_PAYLOAD=$(echo '{}' | jq --arg body "$PR_COMMENT" '.body = $body')
  echo -e "\033[34;1mINFO:\033[0m Adding validate failure comment to PR."
  curl -sS -X POST -H "$AUTH_HEADER" -H "$ACCEPT_HEADER" -H "$CONTENT_HEADER" -d "$PR_PAYLOAD" -L "$PR_COMMENTS_URL" > /dev/null

  exit 0
fi
