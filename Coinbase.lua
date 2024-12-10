--
-- Yet another MoneyMoney Coinbase extension
--
-- This MoneyMoney extension shows your Coinbase wallets and balances using the
-- new Coinbase API v3. It supports an unlimited number of wallets and currency
-- conversions which aren't directly available via the Coinbase API.
--
-- For more information about this extension, check out its GitHub repository:
-- https://github.com/toblux/moneymoney-coinbase-extension
--

-- local variables
local coinbase_api_key_name    -- username
local coinbase_api_private_key -- password
local coinbase_api_hostname = "api.coinbase.com"

local default_currency = "EUR"
local currency_aliases = { ETH2 = "ETH" }
local currency_redirects = { AMP = "USDC", CBETH = "ETH" }
local cached_prices = {}

local connection = nil

WebBanking {
    version     = 1.00,
    url         = "https://" .. coinbase_api_hostname,
    services    = { "Coinbase" },
    description = "View your Coinbase wallets and balances in MoneyMoney"
}

local function base64urlencode(data)
    return MM.base64(data):gsub("+", "-"):gsub("/", "_"):gsub("=", "")
end

-- This function is copied from https://github.com/luckfamousa/coinbase-moneymoney with some minor changes
-- Copyright (c) 2024 Felix Nensa
-- Licensed under the MIT License
local function pad_or_trim(data, length)
    local data_len = #data

    if data_len < length then
        data = string.rep("\0", length - data_len) .. data -- pad with leading zeros
    elseif data_len > length then
        local trimmed = data:match("^\0*")                 -- match leading zeros
        data = data:sub(#trimmed + 1, #trimmed + length)   -- trim leading zeros
    end

    assert(#data == length, "Length of data must match required length")
    return data
end

-- Converts a DER-encoded signature to a concatenated r || s format
-- This function is copied from https://github.com/luckfamousa/coinbase-moneymoney with some minor changes
-- Copyright (c) 2024 Felix Nensa
-- Licensed under the MIT License
local function der_to_rs(der_signature)
    local idx = 1
    assert(der_signature:byte(idx) == 0x30, "SEQUENCE tag (0x30) not found")
    idx = idx + 1

    assert(der_signature:byte(idx) > 0, "Invalid signature length")
    idx = idx + 1

    -- Parse "r" value
    assert(der_signature:byte(idx) == 0x02, "INTEGER type tag (0x02) not found")
    idx = idx + 1

    local r_len = der_signature:byte(idx) -- length of "r"
    assert(r_len > 0, "Invalid length of r")
    idx = idx + 1

    local r = der_signature:sub(idx, idx + r_len - 1)
    idx = idx + r_len

    -- Parse "s" value
    assert(der_signature:byte(idx) == 0x02, "INTEGER type tag (0x02) not found")
    idx = idx + 1

    local s_len = der_signature:byte(idx) -- length of "s"
    assert(s_len > 0, "Invalid length of s")
    idx = idx + 1

    local s = der_signature:sub(idx, idx + s_len - 1)

    -- Ensure "r" and "s" are 32 bytes long
    return pad_or_trim(r, 32) .. pad_or_trim(s, 32)
end

-- This function is copied from https://github.com/luckfamousa/coinbase-moneymoney with some minor changes
-- Copyright (c) 2024 Felix Nensa
-- Licensed under the MIT License
local function create_signature(data_to_sign)
    -- Convert the user's private key
    local base64_key = coinbase_api_private_key
        :gsub("\\n", "")
        :match("-----BEGIN EC PRIVATE KEY-----([A-Za-z0-9+/=]+)-----END EC PRIVATE KEY-----")
    local key = MM.base64decode(base64_key)
    local der = MM.derdecode(MM.derdecode(key)[1][2])
    local d = der[2][2]
    local p = MM.derdecode(der[4][2])[1][2]
    local x = string.sub(p, string.len(p) - 63, string.len(p) - 32)
    local y = string.sub(p, string.len(p) - 31)

    -- create signature
    local signature = MM.ecSign({ curve = "prime256v1", d = d, x = x, y = y }, data_to_sign, "ecdsa sha256")
    local rs_signature = der_to_rs(signature)
    return base64urlencode(rs_signature)
end

local function create_jwt(request_path)
    -- Create JWT header
    local header = {
        alg = "ES256",
        kid = coinbase_api_key_name,
        nonce = MM.binToHex(MM.random(32)),
        typ = "JWT"
    }
    local header_json = JSON():set(header):json()
    local header_enc = base64urlencode(header_json)

    -- Create JWT payload
    local now = os.time()
    local payload = {
        iss = "cdp",
        nbf = now - 30,
        exp = now + 60,
        sub = coinbase_api_key_name,
        uri = "GET" .. " " .. coinbase_api_hostname .. request_path
    }
    local payload_json = JSON():set(payload):json()
    local payload_enc = base64urlencode(payload_json)

    local data_to_sign = header_enc .. "." .. payload_enc
    local signature = create_signature(data_to_sign)
    return data_to_sign .. "." .. signature
end

local function fetch(path, authenticate, cursor)
    local headers = {}
    headers["Accept"] = "application/json"
    headers["Content-Type"] = "application/json"
    if authenticate then
        headers["Authorization"] = "Bearer " .. create_jwt(path)
    end

    local url = url .. path
    if cursor then
        url = url .. "?cursor=" .. cursor
    end

    local content = connection:request("GET", url, nil, nil, headers)
    return JSON(content):dictionary()
end

local function fetch_coinbase_price(conversion_key)
    local prices = fetch("/api/v3/brokerage/market/products/" .. conversion_key)

    if prices["error"] then
        error(conversion_key .. ": " .. prices["message"])
    end

    return tonumber(prices["price"])
end

local function convert_to_default_currency(currency)
    local from_currency = currency_aliases[currency] or currency
    local to_currency = currency_redirects[currency] or default_currency
    local currency_conversion_key = from_currency .. "-" .. to_currency

    local price = cached_prices[currency_conversion_key] or fetch_coinbase_price(currency_conversion_key)
    cached_prices[currency_conversion_key] = price

    if to_currency ~= default_currency then
        price = price * convert_to_default_currency(to_currency)
    end

    return price
end

local function fetch_coinbase_accounts(cursor)
    local response = fetch("/api/v3/brokerage/accounts", true, cursor)
    local accounts = response["accounts"]

    if response["has_next"] then
        local cursor = response["cursor"]
        local next_accounts = fetch_coinbase_accounts(cursor)

        -- Append consecutive accounts
        for _, next_account in ipairs(next_accounts) do
            table.insert(accounts, next_account)
        end
    end

    return accounts
end

-- MoneyMoney app callbacks

function SupportsBank(protocol, bankCode)
    return protocol == ProtocolWebBanking and bankCode == "Coinbase"
end

function InitializeSession(_protocol, _bankCode, username, _reserved, password)
    coinbase_api_key_name = username
    coinbase_api_private_key = password

    connection = Connection()
end

function ListAccounts(_knownAccounts)
    local coinbase_account = {
        name = "Coinbase",
        accountNumber = "Main",
        currency = default_currency,
        portfolio = true,
        type = "AccountTypePortfolio"
    }
    return { coinbase_account }
end

function RefreshAccount(_account, _since)
    local accounts = fetch_coinbase_accounts()
    local securities = {}

    for _, account in ipairs(accounts) do
        local available_balance = tonumber(account["available_balance"]["value"])
        local is_active = account["active"]

        if available_balance > 0 and is_active then
            local account_type = account["type"]

            if account_type == "ACCOUNT_TYPE_FIAT" then
                local amount = available_balance
                if amount >= 0.01 then
                    table.insert(securities, {
                        name = account["name"],
                        amount = available_balance,
                        currency = account["currency"],
                    })
                end
            elseif account_type == "ACCOUNT_TYPE_CRYPTO" then
                local price = convert_to_default_currency(account["currency"])
                local amount = available_balance * price
                if amount >= 0.01 then
                    table.insert(securities, {
                        name = account["name"],
                        quantity = available_balance,
                        amount = amount,
                        price = price
                    })
                end
            else
                print(account_type .. " not supported")
            end
        end
    end

    return { securities = securities }
end

function EndSession()
end
