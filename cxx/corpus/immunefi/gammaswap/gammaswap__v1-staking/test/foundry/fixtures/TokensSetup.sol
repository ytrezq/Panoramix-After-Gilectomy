// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import "forge-std/Test.sol";

import "../../../contracts/tokens/GS.sol";
import "../../../contracts/tokens/RestrictedToken.sol";
import "../../../contracts/tokens/Token.sol";
import "../../../contracts/test/ERC20Mock.sol";

contract TokensSetup is Test {

    ERC20Mock public weth;
    ERC20Mock public usdc;
    ERC20Mock public usdt;
    Token public gs;
    RestrictedToken public esGs;
    RestrictedToken public esGsb;
    RestrictedToken public bnGs;

    function createTokens() public {
        weth = new ERC20Mock("Wrapped Ethereum", "WETH");
        usdc = new ERC20Mock("USDC", "USDC");
        usdt = new ERC20Mock("USDT", "USDT");
        gs = new Token("GS", "GS");
        esGs = new RestrictedToken("Escrowed GS", "esGs", IRestrictedToken.TokenType.ESCROW);
        esGsb = new RestrictedToken("Escrowed GS for Borrowers", "esGs", IRestrictedToken.TokenType.ESCROW);
        bnGs = new RestrictedToken("Bonus GS", "bnGs", IRestrictedToken.TokenType.BONUS);
    }

    function mintTokens(address user, uint256 amount) public {
        usdc.mint(user, amount);
        weth.mint(user, amount);
        usdt.mint(user, amount);
        // gs.mint(user, amount);
        // esGs.mint(user, amount);
        // esGsb.mint(user, amount);
        // bnGs.mint(user, amount);
    }
}