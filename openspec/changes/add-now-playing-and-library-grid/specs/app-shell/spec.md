# Spec Delta

## MODIFIED Requirements

### Requirement: Remote Screen Chrome

The Remote SHALL be a single screen with no tabs. It SHALL present an app bar
with power, cast and remote actions; a shortcut strip linking Home, Movies, TV
Shows, Music and Pictures; a volume-down, mute and volume-up row; a Back,
Fullscreen, Info, Keyboard and Context utility row; and a directional pad whose
accent-coloured arrows and outlined-circle select fill the free space below the
tile rows, with a bare Back control and a touchpad toggle beneath.

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

#### Scenario: Directional pad fills the free space

- **WHEN** the Remote is shown
- **THEN** its status, shortcut, volume and utility rows are pinned to the top
- **AND** the directional pad expands to consume the remaining height
