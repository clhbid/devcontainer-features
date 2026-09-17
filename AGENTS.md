# Agents

**Read `README.md` first** for what this repository is, the Feature layout, platform support, and
why it's public.

This document is **agent-specific** guidance for working effectively in this codebase. This repo
is public — anything in this file, and anything you commit here, is visible outside CLHbid.

### Before Starting Work

1. Read the Layout section in `README.md` — `src/<feature-id>/` is the Feature source,
   `test/<feature-id>/` its test scenarios
1. Assign the issue to yourself — or to the person you are operating as — if that hasn't been
   done already, then set its `Status` to `In progress` on the CLHbid Delivery org project. See
   the `issue-tracker` skill for details

### Before Finishing Work

1. If you added or changed a Feature, bump its `version` in `devcontainer-feature.json` in the
   same pull request — a push to `main` that changes `version` publishes a new release
1. Test the Feature locally with `./scripts/test-features.sh`
1. Push the branch and open a pull request that references the issue it implements — see the
   `open-pr` skill
1. Request review from a human maintainer — see **How a run ends** below

### How a run ends

Passing a Feature test is not finishing. Every run ends in exactly one of these three states — see
the `afk-loop` skill for why, and how each gets reviewed:

| State        | Status             | What to do                                                                                                                                                                      |
| ------------ | ------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Complete** | `Ready for Human`  | Open the pull request ready for review. Only claim this when checks pass, every acceptance criterion is addressed, and the agent brief is complete.                             |
| **Blocked**  | `Waiting on input` | Something you can't resolve would stop the pull request being merged. Leave it as a draft and comment with the specific question or action needed, and the steps to resolve it. |
| **Error**    | `Ready for Human`  | The run failed. Leave the pull request as a draft and comment with what failed, and if possible what action can be taken to resolve the issue.                                  |

## Agent skills

The shared conventions are **installed, not committed**. They live in
[`clhbid/agent-context`](https://github.com/clhbid/agent-context), so nothing here duplicates
them:

| Skill           | What it covers                                                                                                                                                  |
| --------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `issue-tracker` | Issues via `gh`, the `Status` field and how to set it, the board query recipes, triage roles, cycles, labels, the commit convention, and how to decompose work |
| `afk-loop`      | Dispatching work to Copilot, reviewing what comes back, and handling a run that goes wrong                                                                     |
| `open-pr`       | Opening and updating a pull request                                                                                                                             |

This repo has no devcontainer, so nothing installs the skills for you automatically. Install them
by hand with `./scripts/install-agent-skills.sh` — pass an agent name to install elsewhere, e.g.
`./scripts/install-agent-skills.sh copilot`, or `'*'` for every agent it detects.

**If you are reading this without those skills, you have everything you need.** A Copilot coding
agent runs in an environment that has not installed them: the commands above, and **How a run
ends**, are the whole contract. Anything else is reference material for a person or a session with
the skills to hand — never a prerequisite for finishing an issue. If you find you needed something
that isn't here, say so on the pull request, so it can be added to this file rather than restored
as a copy of the docs.
