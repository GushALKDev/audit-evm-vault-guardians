// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

// @audit-answered-question - Why this interface is void?
// @audit-answer - Legacy/Abandoned code. The protocol uses multiple inheritance for adapters instead of implementing a common interface. Should be removed.
// @audit-info - Unused file, should be deleted from codebase.
interface IVaultGuardians {}
