Atlas Demo Template
===================

This repository serves as a starting point for demonstrating the **Human--Atlas--Codex** workflow.\
It includes issue templates with hidden Atlas instructions, a PR review template, workflow documentation, and a bootstrap script for quickly creating demo repositories with projects, labels, and starter issues.

Usage
-----

1.  Install the GitHub CLI (`gh`) and `jq`.

2.  Create a new repository from this template, or run:\
    `./scripts/bootstrap.sh <org-or-user> <new-repo-name> [--private|--public]`

3.  The script will:

    -   Clone the template.

    -   Create a new Project (v2) with status columns.

    -   Add standard workflow labels.

    -   Create a demo issue to start the refinement loop.

Contents
--------

-   `.github/ISSUE_TEMPLATE`: feature and bug forms with Atlas automation hints.

-   `.github/PULL_REQUEST_TEMPLATE.md`: includes AC checklist and Atlas review instructions.

-   `docs/`: workflow introduction and state diagram.

-   `scripts/bootstrap.sh`: sets up a new demo repo with one command.

Purpose
-------

Provide a repeatable, minimal environment for testing and evolving Atlas automation around issue refinement, coding, and review.
