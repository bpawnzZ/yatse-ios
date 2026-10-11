# Spec Delta

## Purpose

How a library section is presented: a poster grid for media whose identity is
artwork, and a list for media that is read as text, so browsing shows many titles
at once instead of one per row.

## ADDED Requirements

### Requirement: Poster Grid for Poster Media

Movies and TV Shows SHALL browse as a two-column grid of poster tiles, and SHALL
remain paginated as more titles are reached.

#### Scenario: Movies render as a grid

- **WHEN** the Movies section is opened
- **THEN** its titles are shown as a two-column grid of poster tiles, not a list

#### Scenario: TV Shows render as a grid

- **WHEN** the TV Shows section is opened
- **THEN** its titles are shown as a two-column grid of poster tiles, not a list

#### Scenario: More titles load on scroll

- **WHEN** the grid is scrolled near its end and more titles remain
- **THEN** the next page of titles is loaded

### Requirement: List for Non-Poster Media

Library sections whose items are read as text SHALL keep a single-column list.

#### Scenario: Music stays a list

- **WHEN** the Artists or Albums section is opened
- **THEN** its rows are shown as a list

#### Scenario: Drill-downs stay lists

- **WHEN** a show's episodes or an artist's albums are opened
- **THEN** they are shown as a list

### Requirement: Poster Tile Content and Action

A poster tile SHALL show the item's artwork, and its title with any detail line,
and SHALL play the item or drill into it as the section defines.

#### Scenario: Tapping a playable tile

- **WHEN** a movie tile is tapped
- **THEN** that movie is played

#### Scenario: Tapping a drill-down tile

- **WHEN** a TV show tile is tapped
- **THEN** the shell drills into that show's episodes

#### Scenario: Missing artwork

- **WHEN** an item has no artwork
- **THEN** its tile shows a placeholder image instead of a blank tile
