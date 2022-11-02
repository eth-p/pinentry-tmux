package main

import (
	"github.com/eth-p/pinentry-tmux/prompt"
)

type PinentryFrontend struct {
	factory func() prompt.Prompt
	impl    prompt.Prompt
}

func NewPinentryFrontend(factory func() prompt.Prompt) *PinentryFrontend {
	return &PinentryFrontend{
		factory: factory,
		impl:    nil,
	}
}

// Get gets the frontend instance.
func (f *PinentryFrontend) Get() prompt.Prompt {
	if f.impl != nil {
		f.impl = f.factory()
	}

	return f.impl
}

// Close closes the frontend, freeing any and all allocated resources.
func (f *PinentryFrontend) Close() error {
	var err error

	if impl, ok := f.impl.(prompt.PromptWithResources); ok {
		err = impl.Close()
	}

	return err
}
