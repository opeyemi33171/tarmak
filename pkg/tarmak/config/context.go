package config

import (
	"errors"
	"fmt"
	"net"

	"github.com/hashicorp/go-multierror"
)

type Context struct {
	Name   string  `yaml:"name,omitempty"` // only alphanumeric lowercase
	Stacks []Stack `yaml:"stacks,omitempty"`

	stackNetwork *StackNetwork

	environment *Environment
}

func (c *Context) Validate() error {
	var result error

	c.stackNetwork = nil
	for posStack, _ := range c.Stacks {
		stack := &c.Stacks[posStack]

		// ensure stack validates
		if err := stack.Validate(); err != nil {
			result = multierror.Append(result, err)
		}

		// ensure there is only a single network stack
		if stack.StackName() == StackNameNetwork {
			if c.stackNetwork == nil {
				c.stackNetwork = stack.Network
			} else {
				result = multierror.Append(result, fmt.Errorf("context '%s' has multiple network stacks", c.GetName()))
			}
		}

	}

	if c.stackNetwork == nil {
		result = multierror.Append(result, fmt.Errorf("context '%s' has no network stack", c.GetName()))
	} else {
		_, err := c.getNetworkCIDR()
		if err != nil {
			result = multierror.Append(result, fmt.Errorf("context '%s' has an incorrect network CIDR: %s", c.GetName(), err))
		}

	}

	return result

}

func (c *Context) getNetworkCIDR() (*net.IPNet, error) {
	if c.stackNetwork == nil {
		return nil, errors.New("no network stack found")
	}

	_, net, err := net.ParseCIDR(c.stackNetwork.NetworkCIDR)
	return net, err
}

func (c *Context) NetworkCIDR() *net.IPNet {
	net, err := c.getNetworkCIDR()
	if err != nil {
		return nil
	}
	return net
}

func (c *Context) RemoteState(stackName string) string {
	return c.environment.RemoteState(c.Name, stackName)
}

func (c *Context) RemoteStateAvailable() bool {
	return c.environment.RemoteStateAvailable()
}

func (c *Context) ProviderEnvironment() ([]string, error) {
	return c.environment.ProviderEnvironment()
}

func (c *Context) GetName() string {
	return fmt.Sprintf("%s-%s", c.environment.Name, c.Name)
}

func (c *Context) GetStateBucketPrefix() string {
	return c.environment.stackState.BucketPrefix
}