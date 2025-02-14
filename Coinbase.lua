--
-- Yet another MoneyMoney Coinbase extension
--
-- This MoneyMoney extension lists your Coinbase wallets and balances. For more
-- information about this extension, check out its GitHub repository:
-- https://github.com/toblux/moneymoney-coinbase-extension
--
-- MIT License
--
-- Copyright (c) 2024-2025 Thorsten Blum
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.
--

-- local variables
local coinbase_api_key_name    -- username
local coinbase_api_private_key -- password
local coinbase_api_hostname = "api.coinbase.com"
local coinbase_api_base_url = "https://" .. coinbase_api_hostname
local coinbase_service_name = "Coinbase Account"

local connection = nil

local AccountTypeApiV2 = {
    FIAT = "fiat",
    WALLET = "wallet"
}

local AccountTypeApiV3 = {
    FIAT = "ACCOUNT_TYPE_FIAT",
    CRYPTO = "ACCOUNT_TYPE_CRYPTO",
    VAULT = "ACCOUNT_TYPE_VAULT"
}

local MimeType = {
    JSON = "application/json",
    TEXT = "text/plain"
}

WebBanking {
    version     = 1.04,
    url         = coinbase_api_base_url,
    services    = { coinbase_service_name },
    description = "View your Coinbase wallets and balances in MoneyMoney"
}

local function base64urlencode(data)
    return MM.base64(data):gsub("+", "-"):gsub("/", "_"):gsub("=", "")
end

local function parse_ec_private_key(key)
    return key
        :gsub("\\n", "") -- remove newline characters
        :gsub("\n", "")  -- remove actual newlines (just in case)
        :match("-----BEGIN EC PRIVATE KEY-----([%sA-Za-z0-9+/=]+)-----END EC PRIVATE KEY-----")
        :gsub("%s+", "") -- remove whitespace
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
local function create_ecdsa_signature(data_to_sign)
    -- Convert the user's private key
    local base64_key = parse_ec_private_key(coinbase_api_private_key)
    if not base64_key then
        error("Invalid private key - please use a valid Coinbase API key")
    end

    local key = MM.base64decode(base64_key)
    local der = MM.derdecode(MM.derdecode(key)[1][2])
    local d = der[2][2]
    local p = MM.derdecode(der[4][2])[1][2]
    local x = string.sub(p, string.len(p) - 63, string.len(p) - 32)
    local y = string.sub(p, string.len(p) - 31)

    -- Create ECDSA signature
    local signature = MM.ecSign({
        curve = "prime256v1",
        d = d,
        x = x,
        y = y
    }, data_to_sign, "ecdsa sha256")

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
    local signature = create_ecdsa_signature(data_to_sign)
    return data_to_sign .. "." .. signature
end

local function fetch(path, authenticate, query_params)
    local query_params = query_params or {}
    local headers = {
        ["Accept"] = MimeType.JSON,
        ["Content-Type"] = MimeType.JSON
    }

    if authenticate then
        headers["Authorization"] = "Bearer " .. create_jwt(path)
    end

    -- Add query params if needed
    local url = url .. path
    local is_first_query_param = true
    for key, value in pairs(query_params) do
        if is_first_query_param then
            url = url .. "?" .. key .. "=" .. value
            is_first_query_param = false
        else
            url = url .. "&" .. key .. "=" .. value
        end
    end

    local content, _charset, mime_type = connection:request("GET", url, nil, nil, headers)
    if mime_type == MimeType.JSON then
        return JSON(content):dictionary()
    elseif mime_type == MimeType.TEXT and content:find("Unauthorized") then
        error("Unauthorized API access - please check your Coinbase API key configuration")
    else
        error("Unknown API error")
    end
end

local function convert_price(prices, from_currency_id, to_currency_id)
    return prices[from_currency_id .. "-" .. to_currency_id]
end

local function convert_to_default_currency(prices, from_currency_id, default_currency_id)
    if from_currency_id == default_currency_id then
        return 1
    end

    local price = convert_price(prices, from_currency_id, default_currency_id)
    if not price then
        price = convert_price(prices, from_currency_id, "USDC")
        if price then
            price = price * convert_price(prices, "USDC", default_currency_id)
        end
    end

    return price
end

local function fetch_api_v2_accounts(query_params)
    local query_params = query_params or {}
    local response = fetch("/v2/accounts", true, query_params)
    local accounts = response.data
    local pagination = response.pagination

    if pagination and pagination.next_starting_after then
        query_params.starting_after = pagination.next_starting_after
        local next_accounts = fetch_api_v2_accounts(query_params)

        -- Append accounts
        for _, next_account in ipairs(next_accounts) do
            table.insert(accounts, next_account)
        end
    end

    return accounts
end

local function fetch_api_v3_accounts(query_params)
    local query_params = query_params or {}
    local response = fetch("/api/v3/brokerage/accounts", true, query_params)
    local accounts = response.accounts

    if response.has_next then
        query_params.cursor = response.cursor
        local next_accounts = fetch_api_v3_accounts(query_params)

        -- Append accounts
        for _, next_account in ipairs(next_accounts) do
            table.insert(accounts, next_account)
        end
    end

    return accounts
end

local function create_security(account_type, name, quantity, price)
    local security = { name = name, amount = quantity * price }
    if account_type == AccountTypeApiV2.WALLET or account_type == AccountTypeApiV3.CRYPTO or account_type == AccountTypeApiV3.VAULT then
        security.quantity = quantity
        security.price = price
    end
    return security
end

local function create_securities_from_api_v2_accounts(prices, default_currency_id)
    local securities = {}

    local api_v2_accounts = fetch_api_v2_accounts({ limit = 100 })
    for _, api_v2_account in ipairs(api_v2_accounts) do
        local account_name = api_v2_account.name

        -- Skip unsupported accounts
        local account_type = api_v2_account.type
        if account_type ~= AccountTypeApiV2.FIAT and account_type ~= AccountTypeApiV2.WALLET then
            print("Unsupported account type: " .. account_type)
            goto continue
        end

        local quantity = tonumber(api_v2_account.balance.amount)
        if quantity > 0 then
            local currency_id = api_v2_account.balance.currency
            local price = convert_to_default_currency(prices, currency_id, default_currency_id)

            if not price then
                print("Price unavailable for currency: " .. currency_id)
            elseif quantity * price >= 0.01 then
                table.insert(securities, create_security(
                    account_type,
                    account_name,
                    quantity,
                    price
                ))
            end
        end

        ::continue::
    end

    return securities
end

local function create_securities_from_api_v3_accounts(prices, default_currency_id)
    local securities = {}

    local api_v3_accounts = fetch_api_v3_accounts({ limit = 100 })
    for _, api_v3_account in ipairs(api_v3_accounts) do
        local account_name = api_v3_account.name

        -- Skip inactive accounts
        if not api_v3_account.active then
            print("Inactive account: " .. account_name)
            goto continue
        end

        -- Skip unsupported accounts
        local account_type = api_v3_account.type
        if account_type ~= AccountTypeApiV3.FIAT and account_type ~= AccountTypeApiV3.CRYPTO and account_type ~= AccountTypeApiV3.VAULT then
            print("Unsupported account type: " .. account_type)
            goto continue
        end

        -- Focus on balances that are on hold (all others should be included in API v2 accounts)
        local balance_on_hold = tonumber(api_v3_account.hold.value)
        if balance_on_hold > 0 then
            local currency_id = api_v3_account.hold.currency
            local price = convert_to_default_currency(prices, currency_id, default_currency_id)

            if not price then
                print("Price unavailable for currency: " .. currency_id)
            elseif balance_on_hold * price >= 0.01 then
                table.insert(securities, create_security(
                    account_type,
                    account_name .. " (on hold)",
                    balance_on_hold,
                    price
                ))
            end
        end

        ::continue::
    end

    return securities
end

local function fetch_api_v3_prices()
    local response = fetch("/api/v3/brokerage/market/products/")
    local products = response.products
    local prices = {}
    for _, product in ipairs(products) do
        prices[product.product_id] = product.price
    end
    return prices
end

local function get_default_currency_id(accounts)
    for _, account in ipairs(accounts) do
        if account.type == AccountTypeApiV3.FIAT then
            return account.currency
        end
    end

    -- Fallback to EUR if no fiat account is found
    return "EUR"
end

-- MoneyMoney App Callbacks

function SupportsBank(protocol, bankCode)
    return protocol == ProtocolWebBanking and bankCode == coinbase_service_name
end

function InitializeSession(_protocol, _bankCode, username, _reserved, password)
    coinbase_api_key_name = username
    coinbase_api_private_key = password

    connection = Connection()
end

function ListAccounts(_knownAccounts)
    local api_v3_accounts = fetch_api_v3_accounts()
    local default_currency_id = get_default_currency_id(api_v3_accounts)

    local coinbase_account = {
        name = "Coinbase",
        accountNumber = "Main",
        currency = default_currency_id,
        portfolio = true,
        type = AccountTypePortfolio
    }
    return { coinbase_account }
end

function RefreshAccount(account, _since)
    local prices = fetch_api_v3_prices()
    local default_currency_id = account.currency

    local api_v2_securities = create_securities_from_api_v2_accounts(prices, default_currency_id)
    local api_v3_securities = create_securities_from_api_v3_accounts(prices, default_currency_id)

    local merged_security_names = {}
    local securities = {}

    for _, api_v2_security in ipairs(api_v2_securities) do
        table.insert(securities, api_v2_security)
        merged_security_names[api_v2_security.name] = true
    end

    for _, api_v3_security in ipairs(api_v3_securities) do
        if not merged_security_names[api_v3_security.name] then
            table.insert(securities, api_v3_security)
        end
    end

    return { securities = securities }
end

function EndSession()
end
