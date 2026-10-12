# Spec Delta

## Purpose

What the Addons destination lists — video add-ons alone — and how those add-ons
and the content reached inside them are presented and acted on.

## ADDED Requirements

### Requirement: Video Add-Ons Only

The Addons destination SHALL list only add-ons that provide browsable video
content. Add-ons of every other kind SHALL NOT be listed.

#### Scenario: Only video add-ons are listed

- **WHEN** the Addons destination is opened
- **THEN** every listed entry is a video add-on
- **AND** skins, scrapers, fonts, resource packs, scripts and repositories are
  not among them

#### Scenario: A plugin source that is not a video add-on is excluded

- **WHEN** the host has an installed add-on that exposes plugin content but does
  not provide video
- **THEN** it is not listed

#### Scenario: No video add-ons are installed

- **WHEN** the host has no video add-ons
- **THEN** the destination states that rather than presenting an empty grid

### Requirement: Disabled Video Add-Ons Remain Listed

A video add-on that is disabled on the host SHALL remain listed, so it can be
enabled again.

#### Scenario: A disabled add-on is still offered

- **WHEN** a video add-on is disabled on the host
- **THEN** it is still listed
- **AND** the destination offers a way to enable it

#### Scenario: The host rejects the change

- **WHEN** enabling or disabling is refused by the host
- **THEN** the destination reports the host's error
- **AND** the listed state is not left claiming a change that did not happen

### Requirement: Add-Ons Presented as a Poster Grid

The Addons destination SHALL present video add-ons as a two-column grid of
tiles. Each tile SHALL show the add-on's artwork, its name, and a detail line.

#### Scenario: Add-ons render as a grid

- **WHEN** the Addons destination is shown
- **THEN** its add-ons are a two-column grid of tiles, not a list of rows

#### Scenario: An add-on has no artwork

- **WHEN** a listed add-on carries no artwork
- **THEN** its tile shows a placeholder rather than a blank tile

#### Scenario: Tapping an add-on opens its content

- **WHEN** a tile is tapped
- **THEN** the content that add-on exposes on the host is opened

#### Scenario: The host refuses to browse an add-on

- **WHEN** the host answers the browse request for an add-on with an error
- **THEN** the error is shown in place of the content
- **AND** the destination is not left blank

### Requirement: Add-On Content Presented as a Poster Grid

Content reached inside a video add-on SHALL be presented as a two-column grid of
tiles, matching the grid the library uses, however deeply it is nested.

#### Scenario: Content renders as a grid

- **WHEN** an add-on's content is opened
- **THEN** its entries are a two-column grid of tiles

#### Scenario: A folder entry drills down

- **WHEN** a tile that represents a folder is tapped
- **THEN** that folder's entries are opened as a further grid

#### Scenario: A playable entry plays

- **WHEN** a tile that represents playable media is tapped
- **THEN** that item is played on the host

#### Scenario: Content carries its own artwork

- **WHEN** an entry inside an add-on has artwork
- **THEN** its tile shows that artwork
- **AND** when it has none, the tile shows a placeholder

### Requirement: Enable and Disable from the Long-Press Menu

The Addons destination SHALL offer enabling and disabling a video add-on from a
long press on its tile, and SHALL NOT depend on a swipe gesture.

#### Scenario: Long press offers the opposite state

- **WHEN** an enabled add-on's tile is long-pressed
- **THEN** the menu offers to disable it
- **AND** when a disabled add-on's tile is long-pressed, the menu offers to
  enable it

#### Scenario: The change is applied

- **WHEN** enabling or disabling is chosen
- **THEN** the host is asked to make the change
- **AND** the tile reflects the new state
