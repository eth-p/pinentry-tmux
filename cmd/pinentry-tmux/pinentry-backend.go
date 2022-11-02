package main

import (
	"errors"

	"github.com/foxcpp/go-assuan/common"
	"github.com/foxcpp/go-assuan/pinentry"

	"github.com/eth-p/pinentry-tmux/prompt"
)

type PinentryBackend struct {
	frontend PinentryFrontend
}

func (p *PinentryBackend) ConvertError(err error) *common.Error {
	// Cancelled.
	if errors.Is(err, prompt.Cancelled) {
		return &common.Error{
			Src:     common.ErrSrcPinentry,
			Code:    common.ErrCanceled,
			SrcName: "pinentry-tmux",
			Message: "Operation cancelled",
		}
	}

	// Unknown.
	return &common.Error{
		Src:     common.ErrSrcPinentry,
		Code:    common.ErrUnexpected,
		SrcName: "pinentry-tmux",
		Message: err.Error(),
	}
}

func (p *PinentryBackend) GetPIN(settings pinentry.Settings) (string, *common.Error) {
	response, err := p.frontend.Get().Password(prompt.PasswordOptions{})
	if err != nil {
		return string(response), nil
	}

	// Handle errors:
}

func RunAsPinentry(tmuxSocket string) error {
	backend := &PinentryBackend{}

	// Create an Assuan server to listen for pinentry commands.
	// When we receive a command, it will be forwarded to the frontend.
	err := pinentry.Serve(pinentry.Callbacks{
		GetPIN: backend.GetPIN,
	}, "pinentry-tmux")

	backend.frontend.Close()
	return err
}
