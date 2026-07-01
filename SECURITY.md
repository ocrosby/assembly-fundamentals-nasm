# Security Policy

## Scope

This repository is a study companion for x86-64 assembly with NASM.
It ships documentation, small demonstration programs, and a
per-example `Makefile`. It does not run a service, expose a network
listener, ship a library other projects depend on, or process
untrusted input.

The example programs are educational. They are **not intended to be
run against attacker-controlled inputs** and should not be linked
into production code.

## Reporting a vulnerability

If you find something you believe should be treated as a security
issue — an unsafe pattern demonstrated in an example, a supply-chain
concern with the CI workflow, or an injected link in the docs — do
**not** open a public issue. Instead:

1. Use GitHub's private vulnerability reporting on this repository
   (Security tab → **Report a vulnerability**), or
2. Email the maintainer directly. Their contact is on their GitHub
   profile.

Expect an acknowledgement within seven days. Fixes for confirmed
issues are shipped as ordinary PRs once the report is triaged.

## Supported versions

This repo is unversioned — only the tip of `main` is maintained. Fix
PRs land on `main`; there are no long-lived support branches.
