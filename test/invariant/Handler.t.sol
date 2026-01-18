// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {VaultGuardians} from "../../src/protocol/VaultGuardians.sol";
import {VaultShares} from "../../src/protocol/VaultShares.sol";
import {IVaultData} from "../../src/interfaces/IVaultData.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Handler is Test {
    VaultGuardians public vaultGuardians;
    IERC20 public weth;
    IERC20 public usdc;
    IERC20 public link;

    // Ghost variables
    mapping(address => bool) public isGuardian;
    mapping(address => mapping(address => address)) public guardianVaults; // user -> token -> vault
    mapping(address => uint256) public ghost_stakeCount;
    address[] public guardians;
    VaultShares[] public allVaults;

    constructor(
        VaultGuardians _vaultGuardians,
        IERC20 _weth,
        IERC20 _usdc,
        IERC20 _link
    ) {
        vaultGuardians = _vaultGuardians;
        weth = _weth;
        usdc = _usdc;
        link = _link;
    }

    /*//////////////////////////////////////////////////////////////
                                ACTIONS
    //////////////////////////////////////////////////////////////*/

    function becomeGuardian(uint256 seed1, uint256 seed2) public {
        // msg.sender is randomized by foundry
        if (isGuardian[msg.sender]) return;
        // Limit number of guardians to avoid Out Of Gas errors
        if (guardians.length > 50) return;

        IVaultData.AllocationData memory allocationData = _getTokenAllocation(seed1, seed2);
        
        uint256 stakePrice = vaultGuardians.getGuardianStakePrice();
        deal(address(weth), msg.sender, stakePrice);
        
        vm.startPrank(msg.sender);
        if (!_safeApprove(weth, address(vaultGuardians), stakePrice)) {
            vm.stopPrank();
            return;
        }
        
        try vaultGuardians.becomeGuardian(allocationData) returns (address vault) {
            isGuardian[msg.sender] = true;
            guardianVaults[msg.sender][address(weth)] = vault;
            ghost_stakeCount[address(weth)]++;
            guardians.push(msg.sender);
            allVaults.push(VaultShares(vault));
        } catch {
            // Ignore failures
        }
        vm.stopPrank();
    }

    function becomeTokenGuardian(uint256 guardianIndex, uint256 seed1, uint256 seed2, bool useUsdc) public {
        if (guardians.length == 0) return;
        
        address guardian = guardians[bound(guardianIndex, 0, guardians.length - 1)];
        
        // Check if guardian mapping still exists for WETH
        if (guardianVaults[guardian][address(weth)] == address(0)) return;

        IERC20 token = useUsdc ? usdc : link;
        
        // Check if already has vault for this token
        if (guardianVaults[guardian][address(token)] != address(0)) return;

        IVaultData.AllocationData memory allocationData = _getTokenAllocation(seed1, seed2);
        uint256 stakePrice = vaultGuardians.getGuardianStakePrice();
        deal(address(token), guardian, stakePrice);
        
        vm.startPrank(guardian);
        
        if (!_safeApprove(token, address(vaultGuardians), stakePrice)) {
            vm.stopPrank();
            return;
        }
        
        try vaultGuardians.becomeTokenGuardian(allocationData, token) returns (address vault) {
            guardianVaults[guardian][address(token)] = vault;
            ghost_stakeCount[address(token)]++;
            allVaults.push(VaultShares(vault));
        } catch {
             // Handle revert
        }
        vm.stopPrank();
    }
    
    function deposit(uint256 vaultIndex, uint256 amount) public {
        if (allVaults.length == 0) return;
        
        VaultShares vault = allVaults[bound(vaultIndex, 0, allVaults.length - 1)];
        if (!vault.getIsActive()) return;

        IERC20 asset = IERC20(vault.asset());
        
        // Use generic bounds, assuming deal works for all tokens
        bool isUsdc = address(asset) == address(usdc);
        if (isUsdc) {
            amount = bound(amount, 1e6, 100_000 * 1e6); // 1 USDC to 100k USDC
        } else {
            amount = bound(amount, 1e15, 10_000 ether); // 0.001 ETH to 10k ETH
        }
        
        deal(address(asset), msg.sender, amount);
        
        vm.startPrank(msg.sender);
        
        if (!_safeApprove(asset, address(vault), amount)) {
            vm.stopPrank();
            return;
        }

        try vault.deposit(amount, msg.sender) {
             // Success
        } catch {
             // Fail
        }
        vm.stopPrank();
    }
    
    function withdraw(uint256 vaultIndex, uint256 shareAmount) public {
         if (allVaults.length == 0) return;
         VaultShares vault = allVaults[bound(vaultIndex, 0, allVaults.length - 1)];
         
         uint256 balance = vault.balanceOf(msg.sender);
         if (balance == 0) return;
         
         shareAmount = bound(shareAmount, 1, balance);
         
         vm.startPrank(msg.sender);
         try vault.withdraw(shareAmount, msg.sender, msg.sender) {
             // Success
         } catch {
             // Fail
         }
         vm.stopPrank();
    }

    function redeem(uint256 vaultIndex, uint256 shareAmount) public {
         if (allVaults.length == 0) return;
         VaultShares vault = allVaults[bound(vaultIndex, 0, allVaults.length - 1)];
         
         uint256 balance = vault.balanceOf(msg.sender);
         if (balance == 0) return;
         
         shareAmount = bound(shareAmount, 1, balance);
         
         vm.startPrank(msg.sender);
         try vault.redeem(shareAmount, msg.sender, msg.sender) {
             // Success
         } catch {
             // Fail
         }
         vm.stopPrank();
    }
    
    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    function _safeApprove(IERC20 token, address spender, uint256 amount) internal returns (bool) {
        (bool success, ) = address(token).call(abi.encodeWithSelector(IERC20.approve.selector, spender, amount));
        return success;
    }

    function _getTokenAllocation(uint256 seed1, uint256 seed2) internal view returns (IVaultData.AllocationData memory) {
        uint256 point1 = bound(seed1, 0, 1000);
        uint256 point2 = bound(seed2, 0, 1000);

        if (point1 > point2) {
            (point1, point2) = (point2, point1);
        }

        uint256 holdAllocation = point1;
        uint256 uniswapAllocation = point2 - point1;
        uint256 aaveAllocation = 1000 - point2;

        return IVaultData.AllocationData(holdAllocation, uniswapAllocation, aaveAllocation);
    }

    function getVaultCount() public view returns (uint256) {
        return allVaults.length;
    }
    
    function getVault(uint256 index) public view returns (VaultShares) {
        return allVaults[index];
    }
}
