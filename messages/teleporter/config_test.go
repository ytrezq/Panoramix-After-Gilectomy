// Copyright (C) 2024, Ava Labs, Inc. All rights reserved.
// See the file LICENSE for licensing terms.

package teleporter

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func TestConfigValidate(t *testing.T) {
	type test struct {
		name     string
		settings map[string]any
		isError  bool
	}

	validAddress := "0x27aE10273D17Cd7e80de8580A51f476960626e5f"

	testCases := []test{
		{
			name: "valid",
			settings: map[string]any{
				"reward-address": validAddress,
			},
			isError: false,
		},
		{
			name: "invalid address",
			settings: map[string]any{
				"reward-address": validAddress[:len(validAddress)-1],
			},
			isError: true,
		},
		{
			name: "invalid key",
			settings: map[string]any{
				"rewardAddress": validAddress,
			},
			isError: true,
		},
	}

	for _, test := range testCases {
		t.Run(test.name, func(t *testing.T) {
			c, err := ConfigFromMap(test.settings)

			if test.isError {
				require.Nil(t, c)
				require.Error(t, err)
			} else {
				require.NotNil(t, c)
				require.NoError(t, err)
			}
		})
	}
}
