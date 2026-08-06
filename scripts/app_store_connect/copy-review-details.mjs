#!/usr/bin/env node

import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { ROOT, attributes, rows, runAsc } from "./_shared.mjs";

function argumentValue(name) {
  const index = process.argv.indexOf(name);
  return index >= 0 ? process.argv[index + 1] : null;
}

function requiredArgument(name) {
  const value = argumentValue(name);
  if (!value) {
    throw new Error(`${name} is required.`);
  }
  return value;
}

function append(args, flag, value) {
  if (value !== null && value !== undefined && String(value).length > 0) {
    args.push(flag, String(value));
  }
}

const sourceVersionID = requiredArgument("--source-version-id");
const targetVersionID = requiredArgument("--target-version-id");
const notesPath = resolve(ROOT, requiredArgument("--notes-path"));

const source = rows(
  runAsc([
    "review",
    "details-for-version",
    "--version-id",
    sourceVersionID,
    "--include-sensitive",
  ]),
)[0];

if (!source) {
  throw new Error("Source App Review details are unavailable for secure copy.");
}

const sourceAttributes = attributes(source);
const target = rows(
  runAsc([
    "review",
    "details-for-version",
    "--version-id",
    targetVersionID,
  ]),
)[0];
const args = target
  ? ["review", "details-update", "--id", target.id]
  : ["review", "details-create", "--version-id", targetVersionID];

append(args, "--contact-first-name", sourceAttributes.contactFirstName);
append(args, "--contact-last-name", sourceAttributes.contactLastName);
append(args, "--contact-email", sourceAttributes.contactEmail);
append(args, "--contact-phone", sourceAttributes.contactPhone);
args.push(
  "--demo-account-required",
  sourceAttributes.demoAccountRequired === true ? "true" : "false",
);

if (sourceAttributes.demoAccountRequired === true) {
  append(args, "--demo-account-name", sourceAttributes.demoAccountName);
  if (
    typeof sourceAttributes.demoAccountPassword !== "string" ||
    sourceAttributes.demoAccountPassword.length === 0 ||
    /redacted/i.test(sourceAttributes.demoAccountPassword) ||
    /^[*•]+$/.test(sourceAttributes.demoAccountPassword)
  ) {
    throw new Error(
      "App Review demo password could not be retrieved securely from the source version.",
    );
  }
  append(
    args,
    "--demo-account-password",
    sourceAttributes.demoAccountPassword,
  );
}

append(args, "--notes", readFileSync(notesPath, "utf8").trim());
runAsc(args);

process.stdout.write(
  `${JSON.stringify(
    {
      status: "ok",
      operation: target ? "updated" : "created",
      credentials_copied_in_memory:
        sourceAttributes.demoAccountRequired === true,
      credentials_logged_or_persisted: false,
    },
    null,
    2,
  )}\n`,
);
