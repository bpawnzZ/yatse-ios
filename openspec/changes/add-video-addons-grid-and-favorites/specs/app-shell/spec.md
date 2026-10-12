# Spec Delta

## MODIFIED Requirements

### Requirement: Navigation Drawer

The shell SHALL provide a drawer that can be opened from the Remote's app bar and
closed by selecting an item or dismissing it. The drawer SHALL list, in order,
Home, Movies, TV Shows, Music, Pvr, Files, Addons, Favorites, Remote, then
Settings and About, and SHALL show a header with the active host name, a host
switcher, and keyboard, mic and search actions. The drawer SHALL NOT expand the
saved favourites into one row each.

#### Scenario: Drawer order and membership

- **WHEN** the drawer is opened
- **THEN** its items appear in the order Home, Movies, TV Shows, Music, Pvr,
  Files, Addons, Favorites, Remote, Settings, About
- **AND** Settings and About are separated from the destinations above them

#### Scenario: Saved favourites are not expanded into the drawer

- **WHEN** the drawer is opened with favourites saved
- **THEN** it offers the Favorites destination instead of one row per favourite

#### Scenario: Selecting a destination

- **WHEN** an item is selected
- **THEN** that destination becomes the shell's current destination
- **AND** the drawer closes
- **AND** the screens pushed within the destination being left are remembered
  rather than discarded
- **AND** the screens previously pushed within the destination being opened are
  restored

#### Scenario: Switching hosts from the header

- **WHEN** the host switcher is used to choose another saved host
- **THEN** the session activates the chosen host
- **AND** the header reflects the newly active host

### Requirement: Honest Unimplemented Destinations

A destination the app does not implement SHALL render a placeholder naming the
destination and stating that it is not available, and SHALL NOT be a dead end.

#### Scenario: Opening an unimplemented destination

- **WHEN** the user opens Pvr
- **THEN** a placeholder screen is shown naming the destination
- **AND** the drawer remains available to leave it

## ADDED Requirements

### Requirement: Destination Navigation Memory

The shell SHALL remember, per destination, the place most recently reached within
it, and SHALL restore that place when the destination is selected again during
the same session.

#### Scenario: Returning to a destination restores the last place

- **WHEN** the user browses into a destination, leaves for another destination,
  and returns
- **THEN** the place last reached within the first destination is shown again

#### Scenario: Memory is kept per destination

- **WHEN** the user browses into one destination and then leaves it
- **THEN** another destination's remembered place is unchanged

#### Scenario: A destination never visited opens at its root

- **WHEN** a destination is opened for the first time in the session
- **THEN** it opens at its own root, with nothing pushed

#### Scenario: Opening a favourite updates the remembered place

- **WHEN** a favourite is opened within a destination
- **THEN** the remembered place for that destination becomes the favourite's place

#### Scenario: Memory does not outlive the session

- **WHEN** the app is relaunched
- **THEN** destinations open at their root rather than at a previously remembered
  place

### Requirement: Drawer Available While Browsing

A screen pushed within a destination SHALL provide the drawer control, so the
drawer can be reached without first returning to that destination's root.

#### Scenario: The drawer control is present on a pushed screen

- **WHEN** a screen pushed inside a destination is shown
- **THEN** the drawer control is available on it

#### Scenario: Opening and closing the drawer keeps the place

- **WHEN** the drawer is opened from a pushed screen, or opened and dismissed
- **THEN** the pushed screen is still in place afterwards
