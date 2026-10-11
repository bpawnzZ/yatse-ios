# Spec Delta

## Purpose

Gives the app a way to prove, on the device and without a debugger attached,
which layer between it and a media centre is working and which one is broken,
before anything is blamed on the wrong layer.

## ADDED Requirements

### Requirement: Host Connection Self-Check

On request the app SHALL run a fixed, ordered probe sequence against one saved
host and SHALL report the outcome of every probe in that sequence, including
probes it did not reach.

#### Scenario: Every probe passes

- **WHEN** the self-check runs against a reachable, correctly configured host
- **THEN** every probe is reported as passed with the value it observed
- **AND** the run is reported as successful overall

#### Scenario: A probe fails

- **WHEN** a probe fails
- **THEN** that probe is reported as failed with its error
- **AND** every probe that depended on it is reported as not run
- **AND** the run is not reported as successful

#### Scenario: Host is unreachable

- **WHEN** the host does not answer
- **THEN** the run terminates within a fixed time budget rather than hanging
- **AND** the probes that were never reached are reported as not run, not as passed

### Requirement: Layer-Attributed Failure Reporting

Every failed probe SHALL identify the connectivity layer it covers, the request
it issued, the error it received, and the corrective action for that layer.

#### Scenario: Credentials are rejected

- **WHEN** the host answers with HTTP 401
- **THEN** the failure is attributed to the credentials layer
- **AND** the reported message names the HTTP status
- **AND** the remediation names the username and password fields

#### Scenario: Transport failure is distinguished from an HTTP failure

- **WHEN** the connection is refused, or times out, or TLS fails
- **THEN** the failure is attributed to the reachability layer
- **AND** the underlying transport detail is preserved verbatim rather than replaced with a generic message

#### Scenario: The host answers with a JSON-RPC error

- **WHEN** a request returns a JSON-RPC error object
- **THEN** the failure is attributed to the layer of the method that produced it
- **AND** the error code and message are reported verbatim

### Requirement: Read-Only Probing

The self-check MUST issue only read-only requests, and MUST NOT alter playback,
input focus, the playlist, volume, mute state, or any host setting.

#### Scenario: Only allowlisted methods are issued

- **WHEN** the self-check runs
- **THEN** every JSON-RPC method it issues is a member of the declared read-only allowlist

#### Scenario: Active playback is undisturbed

- **WHEN** the self-check runs while media is playing
- **THEN** the active player, the current item and the playback position are unchanged afterwards

### Requirement: Portable, Redacted Report

The app SHALL produce a plain-text report of the check containing the app
version, the host address, port and scheme, the server name and version, and
each probe's outcome, and SHALL copy it to the clipboard on request. The report
MUST NOT contain the host password.

#### Scenario: Report is copied

- **WHEN** the user asks for the report to be copied
- **THEN** the clipboard contains the report text
- **AND** the clipboard content does not contain the host password

#### Scenario: Report after a failed run

- **WHEN** the check fails at any probe
- **THEN** a report is still produced
- **AND** it contains the failing probe's layer and error detail

### Requirement: Persisted Host Check Status

The app SHALL persist the outcome of the most recent self-check per host and
SHALL display it in the host list, distinguishing a host that has never been
checked from one that was checked and failed.

#### Scenario: Host has never been checked

- **WHEN** a host has no recorded check
- **THEN** its row indicates that it has not been checked
- **AND** no check timestamp is shown

#### Scenario: Last check failed

- **WHEN** the most recent check for a host failed
- **THEN** its row names the failing layer
- **AND** shows when the check ran

#### Scenario: Last check succeeded

- **WHEN** the most recent check for a host succeeded
- **THEN** its row indicates the host is reachable
- **AND** shows when the check ran
