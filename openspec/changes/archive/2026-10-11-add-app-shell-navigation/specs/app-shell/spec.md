# Spec Delta

## Purpose

Defines how the app is structured around a single active host — the session that
owns player state, the navigation drawer, the persistent mini-player, and the
chrome of the Remote screen — so the app behaves like the host-centric remote it
is specified from rather than a stack of disconnected screens.

## ADDED Requirements

### Requirement: Host-Centric Shell

The app SHALL present a single shell scoped to one active host once a host is
selected, and SHALL present the host picker when no host is active.

#### Scenario: No host is active

- **WHEN** the app launches with no active host
- **THEN** it presents the host picker, not the shell
- **AND** the drawer, app bar and mini-player are not shown

#### Scenario: A host becomes active

- **WHEN** the user selects a host
- **THEN** the app presents the shell for that host
- **AND** the player state for that host is owned above the navigation stack, so
  it survives navigating to any destination and back

#### Scenario: The active host is removed

- **WHEN** the active host is deleted from the saved hosts
- **THEN** the app deactivates the session and returns to the host picker

### Requirement: Navigation Drawer

The shell SHALL provide a drawer that can be opened from the Remote's app bar and
closed by selecting an item or dismissing it. The drawer SHALL list, in order,
Home, Movies, TV Shows, Music, Pvr, Files, Addons, Remote, then Settings and
About, and SHALL show a header with the active host name, a host switcher, and
keyboard, mic and search actions.

#### Scenario: Drawer order and membership

- **WHEN** the drawer is opened
- **THEN** its items appear in the order Home, Movies, TV Shows, Music, Pvr,
  Files, Addons, Remote, Settings, About
- **AND** Settings and About are separated from the destinations above them

#### Scenario: Selecting a destination

- **WHEN** an item is selected
- **THEN** that destination becomes the shell's current destination
- **AND** the drawer closes
- **AND** any detail screens pushed within the previous destination are cleared

#### Scenario: Switching hosts from the header

- **WHEN** the host switcher is used to choose another saved host
- **THEN** the session activates the chosen host
- **AND** the header reflects the newly active host

### Requirement: Persistent Mini-Player

While a player is active on the host, the shell SHALL show a mini-player on every
destination containing a thumbnail, the current title, and stop, play/pause and
next controls. Selecting the mini-player SHALL open the Remote. The mini-player
SHALL NOT be shown when no player is active.

#### Scenario: Something is playing

- **WHEN** a player is active
- **THEN** the mini-player is visible regardless of the current destination
- **AND** it shows a thumbnail, the title, and stop, play/pause and next controls

#### Scenario: Nothing is playing

- **WHEN** no player is active
- **THEN** the mini-player is not shown

#### Scenario: Opening the Remote from the mini-player

- **WHEN** the mini-player is selected
- **THEN** the shell's current destination becomes the Remote

### Requirement: Remote Screen Chrome

The Remote SHALL be a single screen with no tabs. It SHALL present an app bar
showing the host name with power, cast and remote actions; a shortcut strip
linking to Home, Movies, TV Shows, Music and Pictures; a row of volume-down,
mute and volume-up tiles; a row of subtitles, fullscreen, info, keyboard and
list/menu tiles; a directional pad whose arrows use the accent colour and whose
select control is an outlined circle; a bare Back control without a tile; and a
touchpad toggle.

#### Scenario: Shortcut strip navigates

- **WHEN** a shortcut-strip icon is activated
- **THEN** the shell's current destination becomes the matching destination

#### Scenario: Back is a bare control

- **WHEN** the Remote is shown
- **THEN** Back is rendered as an arrow without a surrounding tile
- **AND** it issues the Back key to the host

#### Scenario: Accent is not hardcoded

- **WHEN** the Remote's directional arrows are rendered
- **THEN** their colour comes from the app's configured accent, not a literal
  colour value

### Requirement: Touchpad Mode

The Remote SHALL offer a touchpad mode, toggled from the Remote, in which a swipe
on the touch surface issues a directional key and a tap issues select.

#### Scenario: Swipe issues a direction

- **WHEN** the user swipes in touchpad mode
- **THEN** the key for the dominant swipe axis is issued to the host

#### Scenario: Tap issues select

- **WHEN** the user taps in touchpad mode
- **THEN** the select key is issued to the host

#### Scenario: Toggling the mode

- **WHEN** the touchpad toggle is activated
- **THEN** the touchpad surface is shown in place of the directional pad, and the
  toggle reflects that the mode is on

### Requirement: Playback Artwork Background

While a player is active and the current item carries artwork, the Remote SHALL
render that artwork as a blurred background and render its control tiles
translucently over it.

#### Scenario: Artwork is available

- **WHEN** a player is active and the current item has artwork
- **THEN** the Remote's background is that artwork, blurred
- **AND** the control tiles are translucent

#### Scenario: No artwork

- **WHEN** nothing is playing, or the current item has no artwork
- **THEN** the Remote renders its ordinary background and opaque tiles

### Requirement: Honest Unimplemented Destinations

A destination the app does not implement SHALL render a placeholder naming the
destination and stating that it is not available, and SHALL NOT be a dead end.

#### Scenario: Opening an unimplemented destination

- **WHEN** the user opens Pvr, Files or Addons
- **THEN** a placeholder screen is shown naming the destination
- **AND** the drawer remains available to leave it
