# MoneyMoney Coinbase Extension

This MoneyMoney extension lists your Coinbase wallets and balances.

## Installation

Installing MoneyMoney extensions is documented [here](https://moneymoney-app.com/extensions/) (scroll down to **Installation**).

To use this extension, you have to **create a Coinbase API key** with read-only permissions, which is documented [here](https://help.coinbase.com/exchange/managing-my-account/how-to-create-an-api-key).

Finally, add a new Coinbase account in MoneyMoney with **Account > Add Account > Other > Coinbase Account** and enter your **API key name** and your **EC private key** (copy both values in full, including any newline characters such as `\n`).

## Rationale and features

I was happy with [Martin Wilhelmi's](https://github.com/mnin/coinbase-moneymoney) and [Felix Nensa's](https://github.com/luckfamousa/coinbase-moneymoney) extensions, but they're either no longer maintained or just didn't work for me anymore—mainly because paging isn't implemented and cryptocurrencies like cbETH are missing (at least as of December 2024).

This MoneyMoney extension is inspired by both and adds the following features:

- Unlimited number of wallets (by handling paginated API responses)
- Starting with v1.02, balances on hold are listed separately
- Starting with v1.04, staked assets are working again

## Contributing

Contributions are welcome!

## Contributors

- [Sebastian Grewe](https://github.com/TheSerapher)

## Sponsoring

If you don't have a Coinbase account yet (unlikely if you're looking for this extension, but who knows), feel free to use my [Invite friends link](https://coinbase.com/join/KF96TTX?src=referral-link) to create one.
