package prompt

import "time"

type CommonOptions struct {
	Timeout time.Duration
	
	// Description is a detailed description of what is being requested.
	Description string

	// Title is the window title.
	Title string

	// Buttons are the button labels.
	Buttons struct {
		Confirm string
		Cancel  string
	}
}

type PasswordOptions struct {
	CommonOptions
}
