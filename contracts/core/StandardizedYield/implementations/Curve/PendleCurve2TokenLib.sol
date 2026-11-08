// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "../../../libraries/math/PMath.sol";
import "../../../../interfaces/Curve/ICurvePoolDynamic.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

library PendleCurve2TokenLib {
    uint256 internal constant A_PRECISION = 100;
    uint256 internal constant PRECISION = 10 ** 18;
    uint256 internal constant RATE_0 = 1000000000000000000;
    uint256 internal constant RATE_1 = 1000000000000000000000000000000;
    uint256 internal constant FEE_DENOMINATOR = 10 ** 10;

    uint256 internal constant NCOIN = 2;

    using PMath for uint256;

    function previewAddLiquidity(address pool, address token, uint256 amount) internal view returns (uint256) {
        uint256 amp = ICurvePoolDynamic(pool).A_precise();
        uint256[] memory _amounts = _getTokenAmounts(pool, token, amount);
        uint256[] memory old_balances = _getBalances(pool);
        uint256[] memory new_balances = memcpy(old_balances);

        uint256 D0 = _get_D_mem(pool, old_balances, amp);
        uint256 total_supply = IERC20(pool).totalSupply();

        for (uint256 i = 0; i < NCOIN; ++i) {
            // skip totalSupply = 0 check
            new_balances[i] += _amounts[i];
        }

        uint256 D1 = _get_D_mem(pool, new_balances, amp);
        assert(D1 > D0);

        uint256[] memory fees = new uint256[](2);

        // skip total_supply > 0 check
        uint256 fee = (ICurvePoolDynamic(pool).fee() * NCOIN) / (4 * (NCOIN - 1));
        for (uint256 i = 0; i < NCOIN; ++i) {
            uint256 ideal_balance = (D1 * old_balances[i]) / D0;
            uint256 difference = 0;
            uint256 new_balance = new_balances[i];

            if (ideal_balance > new_balance) {
                difference = ideal_balance - new_balance;
            } else {
                difference = new_balance - ideal_balance;
            }
            fees[i] = (fee * difference) / FEE_DENOMINATOR;
            new_balances[i] -= fees[i];
        }
        uint256 D2 = _get_D_mem(pool, new_balances, amp);
        return (total_supply * (D2 - D0)) / D0;
    }

    function _get_D_mem(address pool, uint256[] memory balances, uint256 _amp) internal view returns (uint256) {
        uint256[] memory _xp = new uint256[](NCOIN);
        uint256[] memory rates = ICurvePoolDynamic(pool).stored_rates();
        _xp[0] = (rates[0] * balances[0]) / PRECISION;
        _xp[1] = (rates[1] * balances[1]) / PRECISION;

        return _get_D(_xp, _amp);
    }

    function _get_D(uint256[] memory _xp, uint256 _amp) internal pure returns (uint256) {
        uint256 S = 0;
        uint256 Dprev = 0;

        for (uint256 k = 0; k < NCOIN; ++k) {
            S += _xp[k];
        }
        if (S == 0) return 0;

        uint256 D = S;
        uint256 Ann = _amp * NCOIN;

        for (uint256 _i = 0; _i < 255; ++_i) {
            uint256 D_P = D;
            for (uint256 k = 0; k < NCOIN; ++k) {
                D_P = (D_P * D) / (_xp[k] * NCOIN);
            }
            Dprev = D;
            D =
                (((Ann * S) / A_PRECISION + D_P * NCOIN) * D) /
                (((Ann - A_PRECISION) * D) / A_PRECISION + (NCOIN + 1) * D_P);

            if (D > Dprev) {
                if (D - Dprev <= 1) {
                    return D;
                }
            } else {
                if (Dprev - D <= 1) {
                    return D;
                }
            }
        }
        assert(false);
    }

    function _getBalances(address pool) internal view returns (uint256[] memory balances) {
        balances = new uint256[](2);
        balances[0] = ICurvePoolDynamic(pool).balances(0);
        balances[1] = ICurvePoolDynamic(pool).balances(1);
    }

    function memcpy(uint256[] memory b) internal pure returns (uint256[] memory a) {
        a = new uint256[](NCOIN);
        for (uint256 i = 0; i < NCOIN; ++i) {
            a[i] = b[i];
        }
    }

    function _getTokenAmounts(
        address pool,
        address token,
        uint256 amount
    ) internal view returns (uint256[] memory res) {
        res = new uint256[](NCOIN);
        res[token == ICurvePoolDynamic(pool).coins(0) ? 0 : 1] = amount;
    }
}
