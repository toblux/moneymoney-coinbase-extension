# MoneyMoney Coinbase Extension

This MoneyMoney extension lists your Coinbase wallets and balances.

## Installation

Installing MoneyMoney extensions is documented [here](https://moneymoney-app.com/extensions/) (scroll down to **Installation**).

To use this extension, you have to **create a Coinbase API key** with read-only permissions. Coinbase keeps changing its documentation, but what seems to work best for now is to create your API key [here](https://www.coinbase.com/settings/api).

**Please note:** If you create your API key using the Coinbase Developer Platform (CDP), make sure to select **ECDSA** as the signature algorithm under **Advanced Settings**. Other algorithms are currently not supported by this extension.

Finally, add a new Coinbase account in MoneyMoney with **Account > Add Account > Other > Coinbase Account** and enter your **API key name** and your **EC private key** (copy both values in full, including any newline characters such as `\n`).

## Rationale and features

I had been happy with [Martin Wilhelmi's](https://github.com/mnin/coinbase-moneymoney) and [Felix Nensa's](https://github.com/luckfamousa/coinbase-moneymoney) extensions, but they're either no longer maintained or just didn't work for me anymore—mainly because paging isn't implemented and cryptocurrencies like cbETH are missing (at least as of December 2024).

This MoneyMoney extension is inspired by both and adds the following features:

- Unlimited number of wallets (by handling paginated API responses)
- Lists all your crypto and cash assets (including stablecoins)
- Balances on hold and staked assets are listed separately

## Contributing

Contributions are welcome!

## Contributors

- [Sebastian Grewe](https://github.com/TheSerapher)

## Sponsoring

If you don't have a Coinbase account yet (unlikely if you're looking for this extension, but who knows), feel free to use my [Invite friends link](https://coinbase.com/join/KF96TTX?src=referral-link) to create one.

If you enjoy this extension, please consider a donation to the following addresses:

- Bitcoin (BTC): `bc1qfctuxg44nftfd5k5mnl7j79n2e04skc66dwp4g`
- Ethereum (ETH): `0xAAdde3aa345a87C21AD4bB674C9C3f02783F5a7D`
- Solana (SOL): `FvYW7nboe9jmEpw9aqw8KCpvJiohverjn1ACTacAZnAd`

[Say hi](mailto:thorsten.blum+mm@toblux.com) if you want to be added to the (currently empty) list of sponsors. Thank you!
