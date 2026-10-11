# Spec Delta

## Purpose

The full-screen Now Playing surface opened from the mini-player: what is playing,
how far in it is, and the controls and stream choices for it — without leaving the
app for the television.

## ADDED Requirements

### Requirement: Opening the Now Playing Overlay

The app SHALL present a Now Playing overlay when the mini-player is activated
while a player is active. Activating the mini-player SHALL NOT change the shell's
destination.

#### Scenario: The mini-player opens the overlay

- **WHEN** a player is active and the mini-player is tapped
- **THEN** the Now Playing overlay is presented
- **AND** the shell's current destination is unchanged

#### Scenario: No player is active

- **WHEN** no player is active
- **THEN** the mini-player is not shown and the overlay cannot be opened

#### Scenario: Dismissing the overlay

- **WHEN** the overlay is dismissed
- **THEN** the shell returns to the destination it was on

### Requirement: See-Through Artwork Backdrop

The overlay SHALL render the current item's artwork as its backdrop with a
translucent scrim, so the overlay's controls sit over a see-through image of what
is playing.

#### Scenario: Artwork is available

- **WHEN** the current item carries artwork
- **THEN** the overlay's backdrop is that artwork
- **AND** the controls are drawn over a translucent scrim

#### Scenario: No artwork

- **WHEN** the current item has no artwork
- **THEN** the overlay renders its ordinary surface background

### Requirement: Seek Slider

The overlay SHALL show a seek slider with the elapsed time and the total
duration, tracking playback position and seeking the player when the user drags
it.

#### Scenario: Position tracks playback

- **WHEN** playback position advances
- **THEN** the slider and the elapsed-time label reflect the new position

#### Scenario: Dragging seeks

- **WHEN** the user releases the slider at a new position
- **THEN** the player seeks to that position

### Requirement: Transport Controls

The overlay SHALL provide previous, rewind, play/pause, forward, next and stop
controls, each issuing the matching player command.

#### Scenario: Play/pause reflects state

- **WHEN** the item is playing
- **THEN** the control shows pause and pauses playback when activated
- **AND** when the item is paused it shows play and resumes playback

#### Scenario: Skipping

- **WHEN** next or previous is activated
- **THEN** the player moves to the next or previous item

#### Scenario: Stop

- **WHEN** stop is activated
- **THEN** playback stops

### Requirement: Repeat and Shuffle

The overlay SHALL show repeat and shuffle controls that reflect the player's
current mode and change it when activated.

#### Scenario: Cycling repeat

- **WHEN** repeat is activated
- **THEN** the player's repeat mode advances through off, all and one

#### Scenario: Toggling shuffle

- **WHEN** shuffle is activated
- **THEN** the player's shuffle mode is inverted

### Requirement: Stream Selection

The overlay SHALL let the user choose the active audio stream and subtitle
stream, and change the video/zoom mode, for the current item.

#### Scenario: Choosing an audio stream

- **WHEN** the user selects an audio stream from the list
- **THEN** the player switches to that audio stream

#### Scenario: Choosing a subtitle stream

- **WHEN** the user selects a subtitle stream, or turns subtitles off
- **THEN** the player switches to that stream, or disables subtitles

#### Scenario: Changing video/zoom

- **WHEN** the video/zoom control is activated
- **THEN** the player's zoom/aspect mode advances

### Requirement: Item Information

The overlay SHALL show the current item's details — at least its title and
overview — without leaving the overlay.

#### Scenario: Viewing details

- **WHEN** the Info action is activated
- **THEN** the current item's title, overview and any available metadata are shown

### Requirement: Queue

The overlay SHALL list the current playlist and let the user jump to or remove an
entry.

#### Scenario: Jumping within the queue

- **WHEN** a queue entry is selected
- **THEN** playback moves to that entry

#### Scenario: Removing an entry

- **WHEN** a queue entry is removed
- **THEN** that entry is removed from the playlist

#### Scenario: Empty queue

- **WHEN** the queue has no entries
- **THEN** the overlay states that the queue is empty
