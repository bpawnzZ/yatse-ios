# Spec Delta

## Purpose

Saved places the user can return to — where they are listed, how they are
presented, what a favourite records about the place it points at, and how one is
added or removed while browsing.

## ADDED Requirements

### Requirement: A Favourite Identifies a Place

A favourite SHALL identify a place the shell can navigate to — a library section,
a show's episodes, an artist's albums, or a directory path — and SHALL be stored
durably on the device.

#### Scenario: A favourite survives a relaunch

- **WHEN** a place is saved and the app is relaunched
- **THEN** the favourite is still listed

#### Scenario: The same place is saved twice

- **WHEN** a place that is already saved is saved again
- **THEN** it replaces the existing favourite rather than appearing twice

#### Scenario: A stored favourite no longer decodes

- **WHEN** the stored favourites cannot be read
- **THEN** the app starts with no favourites rather than failing to launch

### Requirement: Favorites Destination

The drawer SHALL list a Favorites destination, and it SHALL present the saved
favourites as a two-column grid of tiles.

#### Scenario: The destination is listed

- **WHEN** the drawer is opened
- **THEN** Favorites is among its destinations

#### Scenario: Favourites render as a grid

- **WHEN** the Favorites destination is opened
- **THEN** the saved favourites are a two-column grid of tiles, not a list

#### Scenario: Nothing is saved

- **WHEN** no favourites are saved
- **THEN** the destination states that rather than presenting an empty grid

#### Scenario: The drawer no longer expands the favourites

- **WHEN** the drawer is opened with favourites saved
- **THEN** it shows the Favorites destination instead of one row per favourite

### Requirement: Favourite Artwork

A favourite SHALL record the artwork of the place it was saved from, and its tile
SHALL show that artwork. A favourite with no recorded artwork SHALL show a
placeholder.

#### Scenario: A saved place carries its artwork

- **WHEN** a place whose entry has artwork is saved
- **THEN** its tile in the Favorites destination shows that artwork

#### Scenario: A favourite has no artwork

- **WHEN** a favourite has no artwork recorded, or the entry it was saved from
  had none
- **THEN** its tile shows a placeholder rather than a blank tile

#### Scenario: A favourite saved before artwork was recorded

- **WHEN** a favourite saved by an earlier build is read
- **THEN** it remains valid and lists with a placeholder tile

### Requirement: Adding and Removing While Browsing

A long press on an entry inside a video add-on SHALL offer to save that place as
a favourite, and SHALL offer to remove it when that place is already saved. The
favourite SHALL be titled with the entry's displayed name.

#### Scenario: Long press offers to save

- **WHEN** an entry inside a video add-on that is not saved is long-pressed
- **THEN** the menu offers to add it to favorites

#### Scenario: Long press offers to remove

- **WHEN** an entry whose place is already saved is long-pressed
- **THEN** the menu offers to remove it from favorites

#### Scenario: Saving takes effect

- **WHEN** adding to favorites is chosen
- **THEN** the place appears in the Favorites destination
- **AND** long-pressing it again offers removal

#### Scenario: Removing takes effect

- **WHEN** removing from favorites is chosen
- **THEN** the place is no longer listed in the Favorites destination

### Requirement: Favourite Opens Its Place

Selecting a favourite SHALL navigate to the place it was saved from: a library
section becomes the current destination, and a deeper place is opened within its
destination.

#### Scenario: A section favourite switches destination

- **WHEN** a favourite that names a library section is selected
- **THEN** that section becomes the current destination

#### Scenario: A directory favourite opens that directory

- **WHEN** a favourite that names a directory is selected
- **THEN** that directory's contents are shown

#### Scenario: A deeper favourite is opened within its destination

- **WHEN** a favourite that names a show's episodes or an artist's albums is
  selected
- **THEN** that place is opened as a screen within the destination it belongs to
