package stdio

import (
	"github.com/chzyer/readline"

	"github.com/eth-p/pinentry-tmux/prompt"
)

// Prompt is a pinentry-tmux prompt implementation that uses STDIO.
// This is meant for development and testing, and shouldn't be used in the final application.
type Prompt struct {
}

var _ prompt.Prompt = &Prompt{}

// Password requests a password/PIN.
func (p *Prompt) Password(options prompt.PasswordOptions) ([]byte, error) {
	password, err := readline.Password(options.Description)
	if err != nil {
		// TODO(eth-p): Wrap me.
		return nil, err
	}

	return password, nil
}
