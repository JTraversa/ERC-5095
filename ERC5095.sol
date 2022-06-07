// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

import "./ERC/ERC20Permit.sol";
import "./Interfaces/IAdapter.sol"; 
import "./Interfaces/IERC5095.sol";  
import "./Interfaces/IRedeemer.sol";

abstract contract ERC5095 is ERC20Permit, IERC5095 {
    /// @dev unix timestamp when the token can be redeemed
    uint256 public override immutable maturity;
    /// @dev address of the token that is redeemed
    address public override immutable underlying;
    
    //////////OPTIONAL///////////////// (Allows the calculation and distribution of yield post maturity)
    /// @dev benchmark `exchangeRate` at maturity
    uint256 public override maturityRate;
    /// @dev address and interface for an external custody contract (necessary for some project's backwards compatability)
    IRedeemer public immutable redeemer;
    /// @dev address and interface for an external cToken adapter (reads exchangeRate across a variety of protocol tokens)
    IAdapter public adapter;
    /// @dev address of a cToken
    address public cToken;

    error Maturity(uint256 maturity);  

    constructor(address u, uint256 m, address a, address r) {
        underlying = u;
        maturity = m;
        adapter = IAdapter(a);
        redeemer = IRedeemer(r);
    }

    /// @notice Post maturity converts an amount of principal tokens to an amount of underlying that would be returned. Returns 0 pre-maturity.
    function convertToUnderlying(uint256 principalAmount) external override view returns (uint256){
        if (block.timestamp < maturity) {
            return 0;
        }
        return (principalAmount * (adapter.exchangeRateCurrent(cToken) / maturityRate));
    }
    /// @notice Post maturity converts a desired amount of underlying tokens returned to principal tokens needed. Returns 0 pre-maturity.
    function convertToPrincipal(uint256 underlyingAmount) external override view returns (uint256){
        if (block.timestamp < maturity) {
            return 0;
        }
        return(underlyingAmount * maturityRate / adapter.exchangeRateCurrent(cToken));
    }
    /// @notice Post maturity calculates the amount of principal tokens a user can redeem. Returns 0 pre-maturity.
    function maxRedeem(address owner) external override view returns (uint256){
        if (block.timestamp < maturity) {
            return 0;
        }
        return(_balanceOf[owner]);
    }
    /// @notice Post maturity simulates the effects of redeemption at the current block. Returns 0 pre-maturity.
    function previewRedeem(uint256 principalAmount) external override view returns (uint256){
        if (block.timestamp < maturity) {
            return 0;
        }
        return(principalAmount * (adapter.exchangeRateCurrent(cToken) / maturityRate));
    }
    /// @notice Post maturity calculates the amount of underlying tokens a user can withdraw. Returns 0 pre-maturity.
    function maxWithdraw(address owner) external override view returns (uint256){
        if (block.timestamp < maturity) {
            return 0;
        }
        return(_balanceOf[owner] * (adapter.exchangeRateCurrent(cToken) / maturityRate));
    }
    /// @notice Post maturity simulates the effects of withdrawal at the current block. Returns 0 pre-maturity.
    function previewWithdraw(uint256 underlyingAmount) external override view returns (uint256){
        if (block.timestamp < maturity) {
            return 0;
        }
        return(underlyingAmount * maturityRate / adapter.exchangeRateCurrent(cToken));
    }
    /// @notice At or after maturity, Burns principalAmount from owner and sends exactly underlyingAmount of underlying tokens to receiver.
    function withdraw(uint256 underlyingAmount, address owner, address receiver) external override returns (uint256 principalAmount){
        if (maturityRate == 0) {
            if (block.timestamp < maturity) {
                revert Maturity(maturity);
            }
            maturityRate = adapter.exchangeRateCurrent(cToken);
            return redeemer.adminRedeem(underlying, maturity, owner, receiver, underlyingAmount);
        }
        return redeemer.adminRedeem(underlying, maturity, owner, receiver, (underlyingAmount * maturityRate / adapter.exchangeRateCurrent(cToken)));
    }
    /// @notice At or after maturity, burns exactly principalAmount of Principal Tokens from from and sends underlyingAmount of underlying tokens to to.
    function redeem(uint256 principalAmount, address owner, address receiver) external override returns (uint256 underlyingAmount){
        if (maturityRate == 0) {
            if (block.timestamp < maturity) {
                revert Maturity(maturity);
            }
            maturityRate = adapter.exchangeRateCurrent(cToken);
        }
        return redeemer.adminRedeem(underlying, maturity, owner, receiver, principalAmount);
    }
}
