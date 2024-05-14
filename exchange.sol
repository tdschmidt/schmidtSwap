// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./token.sol";
import "hardhat/console.sol";

contract TokenExchange is Ownable {
    string public exchange_name = "schmidtSwap";

    address tokenAddr = 0x5FbDB2315678afecb367f032d93F642f64180aa3; // TODO: paste token contract address here
    Token public token = Token(tokenAddr);

    // Liquidity pool for the exchange
    uint256 private token_reserves = 0;
    uint256 private eth_reserves = 0;

    mapping(address => uint256) private lps;

    // Needed for looping through the keys of the lps mapping
    address[] private lp_providers;

    // liquidity rewards
    uint256 private swap_fee_numerator = 5;
    uint256 private swap_fee_denominator = 100;

    // Constant: x * y = k
    uint256 private k;

    uint256 private constant fixed_denom = 10000000;

    constructor() {}

    // Function createPool: Initializes a liquidity pool between your Token and ETH.
    // ETH will be sent to pool in this transaction as msg.value
    // amountTokens specifies the amount of tokens to transfer from the liquidity provider.
    // Sets up the initial exchange rate for the pool by setting amount of token and amount of ETH.
    function createPool(uint256 amountTokens) external payable onlyOwner {
        // This function is already implemented for you; no changes needed.

        // require pool does not yet exist:
        require(token_reserves == 0, "Token reserves was not 0");
        require(eth_reserves == 0, "ETH reserves was not 0.");

        // require nonzero values were sent
        require(msg.value > 0, "Need eth to create pool.");
        uint256 tokenSupply = token.balanceOf(msg.sender);
        require(
            amountTokens <= tokenSupply,
            "Not have enough tokens to create the pool"
        );
        require(amountTokens > 0, "Need tokens to create pool.");

        token.transferFrom(msg.sender, address(this), amountTokens);
        token_reserves = token.balanceOf(address(this));
        eth_reserves = msg.value;
        k = token_reserves * eth_reserves;
    }

    // Function removeLP: removes a liquidity provider from the list.
    // This function also removes the gap left over from simply running "delete".
    function removeLP(uint256 index) private {
        require(
            index < lp_providers.length,
            "specified index is larger than the number of lps"
        );
        lp_providers[index] = lp_providers[lp_providers.length - 1];
        lp_providers.pop();
    }

    // Function getSwapFee: Returns the current swap fee ratio to the client.
    function getSwapFee() public view returns (uint256, uint256) {
        return (swap_fee_numerator, swap_fee_denominator);
    }

    // ============================================================
    //                    FUNCTIONS TO IMPLEMENT
    // ============================================================

    /* ========================= Liquidity Provider Functions =========================  */

    function convert_eth_to_token_rate() public view returns (uint256) {
        return (fixed_denom * token_reserves) / eth_reserves;
    }

    function convert_token_to_eth_rate() public view returns (uint256) {
        return (fixed_denom * eth_reserves) / token_reserves;
    }

    // Function addLiquidity: Adds liquidity given a supply of ETH (sent to the contract as msg.value).
    // You can change the inputs, or the scope of your function, as needed.
    function addLiquidity(uint256 max_exchange_rate, uint256 min_exchange_rate)
        external
        payable
    {
        addFees();
        require(msg.value > 0, "Must provide positive value");

        uint256 conversion_rate = convert_eth_to_token_rate();

        uint256 token_to_add = (conversion_rate * msg.value) / fixed_denom;
        uint256 tokenSupply = token.balanceOf(msg.sender);
        require(
            tokenSupply >= token_to_add,
            "Total allowance is less than required token transfer"
        );

        console.log(
            "exchage_rate, min_exchange_rate, max_exchange_rate: ",
            conversion_rate,
            min_exchange_rate,
            max_exchange_rate
        );
        require(
            conversion_rate > min_exchange_rate &&
                conversion_rate < max_exchange_rate,
            "Failed due to slippage"
        );

        token.transferFrom(msg.sender, address(this), token_to_add);

        //maybe change this line see ed for update time
        token_reserves = token.balanceOf(address(this));
        uint256 new_eth_reserves = eth_reserves + msg.value;

        if (lps[msg.sender] == 0) {
            lp_providers.push(msg.sender);
        }

        for (uint256 i = 0; i < lp_providers.length; i++) {
            uint256 new_equity = (lps[lp_providers[i]] * eth_reserves) /
                new_eth_reserves;
            if (lp_providers[i] == msg.sender) {
                new_equity += (fixed_denom * msg.value) / new_eth_reserves;
            }
            lps[lp_providers[i]] = new_equity;
        }

        eth_reserves = new_eth_reserves;
        k = token_reserves * eth_reserves;
    }

    // Function removeLiquidity: Removes liquidity given the desired amount of ETH to remove.
    // You can change the inputs, or the scope of your function, as needed.
    function removeLiquidity(
        uint256 amountETH,
        uint256 max_exchange_rate,
        uint256 min_exchange_rate
    ) public payable {
        addFees();

        uint256 entitledETH = (lps[msg.sender] * eth_reserves) / fixed_denom;
        require(entitledETH >= amountETH, "Insuficient funds");
        require(amountETH < eth_reserves, "Insufficent funds");
        //double check this
        uint256 amountTOK = (amountETH * token_reserves) / eth_reserves;
        require(amountTOK < token_reserves, "Not enough reserves");

        uint256 exchange_rate = (token_reserves * 10000000) / eth_reserves;
        console.log(
            "exchage_rate, min_exchange_rate, max_exchange_rate: ",
            exchange_rate,
            min_exchange_rate,
            max_exchange_rate
        );
        require(
            exchange_rate > min_exchange_rate &&
                exchange_rate < max_exchange_rate,
            "Failed due to slippage"
        );

        token.transfer(msg.sender, amountTOK);
        payable(msg.sender).transfer(amountETH);

        //maybe change this line see ed for update time
        token_reserves = token.balanceOf(address(this));
        uint256 new_eth_reserves = eth_reserves - amountETH;

        for (uint256 i = 0; i < lp_providers.length; i++) {
            if (lp_providers[i] == msg.sender) {
                lps[lp_providers[i]] =
                    lps[lp_providers[i]] -
                    (amountETH * fixed_denom) /
                    eth_reserves;
            }

            uint256 new_equity = (lps[lp_providers[i]] * eth_reserves) /
                new_eth_reserves;
            lps[lp_providers[i]] = new_equity;
        }

        eth_reserves = new_eth_reserves;
        //calculate K differently
        k = token_reserves * eth_reserves;
    }

    // Function removeAllLiquidity: Removes all liquidity that msg.sender is entitled to withdraw
    // You can change the inputs, or the scope of your function, as needed.
    function removeAllLiquidity(
        uint256 max_exchange_rate,
        uint256 min_exchange_rate
    ) external payable {
        addFees();

        uint256 amountETH = (lps[msg.sender] * eth_reserves) / fixed_denom;

        require(amountETH < eth_reserves, "Insufficent funds");
        //double check this
        uint256 amountTOK = (amountETH * token_reserves) / eth_reserves;
        require(amountTOK < token_reserves, "Not enough reserves");
        //and this
        uint256 exchange_rate = (token_reserves * 10000000) / eth_reserves;

        console.log(
            "exchage_rate, min_exchange_rate, max_exchange_rate: ",
            exchange_rate,
            min_exchange_rate,
            max_exchange_rate
        );

        require(
            exchange_rate > min_exchange_rate &&
                exchange_rate < max_exchange_rate,
            "Failed due to slippage"
        );

        token.transfer(msg.sender, amountTOK);
        payable(msg.sender).transfer(amountETH);

        //maybe change this line see ed for update time
        token_reserves = token.balanceOf(address(this));
        uint256 new_eth_reserves = eth_reserves - amountETH;

        for (uint256 i = 0; i < lp_providers.length; i++) {
            if (lp_providers[i] == msg.sender) {
                removeLP(i);
            } else {
                uint256 new_equity = (lps[lp_providers[i]] * eth_reserves) /
                    new_eth_reserves;
                lps[lp_providers[i]] = new_equity;
            }
        }

        eth_reserves = new_eth_reserves;
        //calculate K differently
        k = token_reserves * eth_reserves;
    }

    /***  Define additional functions for liquidity fees here as needed ***/

    function addFees() public payable {
        if (
            address(this).balance > eth_reserves &&
            token.balanceOf(address(this)) > token_reserves
        ) {
            uint256 extra_eth = address(this).balance - eth_reserves;
            uint256 extra_token = token.balanceOf(address(this)) -
                token_reserves;

            uint256 conversion_rate = (eth_reserves * fixed_denom) /
                token_reserves;

            uint256 maxETH = (conversion_rate * extra_token) / fixed_denom;
            uint256 token_to_add = 0;

            //token limiting factor
            if (extra_eth >= maxETH) {
                token_to_add = extra_token;
            } else {
                maxETH = extra_eth;
                token_to_add = (maxETH * token_reserves) / eth_reserves;
            }

            eth_reserves += maxETH;
            token_reserves += token_to_add;
            k = eth_reserves * token_reserves;
        }
    }

    /* ========================= Swap Functions =========================  */

    // Function swapTokensForETH: Swaps your token with ETH
    // You can change the inputs, or the scope of your function, as needed.
    function swapTokensForETH(uint256 amountTokens, uint256 max_exchange_rate)
        external
        payable
    {
        uint256 amount_token_minus_fee = amountTokens -
            (amountTokens * swap_fee_numerator) /
            swap_fee_denominator;
        uint256 new_token_reserves = token_reserves + amount_token_minus_fee;
        uint256 new_eth_reserves = k / new_token_reserves;
        uint256 eth_to_send = eth_reserves - new_eth_reserves;

        uint256 tokenSupply = token.balanceOf(msg.sender);
        require(
            amountTokens <= tokenSupply,
            "User does not have enough tokens"
        );

        uint256 exchange_rate = convert_token_to_eth_rate(); //optimize for rounding?

        console.log(
            "exchange_rage, max_rate: ",
            exchange_rate,
            max_exchange_rate
        );
        require(exchange_rate < max_exchange_rate, "Failed due to slippage");
        //Version for liquidity rewards commented out below
        //eth_to_send = (eth_to_send * swap_fee_denominator - swap_fee_numerator) / swap_fee_denominator;
        require(eth_to_send <= eth_reserves - 1);
        //Below commented out handles slippage
        //require(token_reserves / eth_reserves <= max_exchange_rate); //add maxexrate as parameter, use denom for divis

        eth_reserves = new_eth_reserves;
        token_reserves = new_token_reserves;

        payable(msg.sender).transfer(eth_to_send);
        token.transferFrom(msg.sender, address(this), amountTokens);
    }

    // Function swapETHForTokens: Swaps ETH for your tokens
    // ETH is sent to contract as msg.value
    // You can change the inputs, or the scope of your function, as needed.
    function swapETHForTokens(uint256 max_exchange_rate) external payable {
        uint256 amount_eth_minus_fee = msg.value -
            (msg.value * swap_fee_numerator) /
            swap_fee_denominator;

        uint256 new_eth_reserves = eth_reserves + amount_eth_minus_fee;
        uint256 new_token_reserves = k / new_eth_reserves;

        uint256 tokens_to_send = token_reserves - new_token_reserves;

        uint256 exchange_rate = convert_eth_to_token_rate();
        console.log(
            "exchange_rage, max_rate: ",
            exchange_rate,
            max_exchange_rate
        );

        require(exchange_rate < max_exchange_rate, "Failed due to slippage");

        require(tokens_to_send <= token_reserves - 1);

        token_reserves = new_token_reserves;
        eth_reserves = new_eth_reserves;

        token.transfer(msg.sender, tokens_to_send);
    }
}
