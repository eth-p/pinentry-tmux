package prompt

type Prompt interface {

	// Password requests a password/PIN.
	Password(options PasswordOptions) ([]byte, error)
}

type PromptWithResources interface {
	Prompt

	// Close frees the resources that were allocated by the prompt implementation.
	Close() error
}
