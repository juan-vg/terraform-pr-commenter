# Changelog

## v2.1.0

- Link to logs added to all types
- Add the option to make the logs link more accurate
  - New optional input argument `commenter_job_name` to specify the job name for the logs link
  - New optional input argument `commenter_step_name` to specify the step name for the logs link
- Standardize the chars limit handling 

## v2.0.0

- Switch from raw Terraform output as input, to a file containing the output. This is meant to overcome the `Argument list too long` error
  - The argument `commenter_input` no longer exists in favor of `commenter_input_file`

## v1.6.1

- Improve char-limit handling for plan comments
  - Keep 65000 chars instead of 65300 to make enough room for comment wrapper
  - Keep the last chars instead of the first ones when truncating (they're usually more useful)
- Always add a link to full logs on plan comments

## v1.6.0

- Bump to Terraform v1.9.0 internally (fixes `curl` problem)
- Removes the cleaning of plan's last lines

## v1.5.0

- Bump to Terraform v1.0.6 internally (only affects `fmt`)
- Fix Terraform v1 `plan` output truncation

## v1.4.0

- Bump to Terraform v0.15.0 internally (only affects `fmt`)
- Change the way `plan`s are truncated after introduction of new horizontal break in TF v0.15.0
- Add `validate` comment handling
- Update readme

## v1.3.0

- Bump to Terraform v0.14.9 internally (only affects `fmt`)
- Fix output truncation in Terraform v0.14 and above

## v1.2.0

- Bump to Terraform v0.14.5 internally (only affects `fmt`)
- Change to leave `fmt` output as-is
- Add colourisation to `plan` diffs where there are changes (on by default, controlled with `HIGHLIGHT_CHANGES` environment variable)
- Update readme

## v1.1.0

- Adds better parsing for Terraform v0.14

## v1.0.0

- Initial release.
