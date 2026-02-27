local PRECISION = 8
local CTX_LEN = 8

local function makePredictor()
    -- P(0) for each context, scaled by PRECISION, from 1 to PRECISION - 1
    local prob0 = {}
    for ctx = 0, bit32.lshift(1, CTX_LEN) - 1 do
        prob0[ctx] = PRECISION / 2
    end
    local ctx = 0
    return {
        getProbability = function()
            return prob0[ctx]
        end,
        feedBit = function(bit)
            if bit == 0 then
                prob0[ctx] = math.min(prob0[ctx] + 1, PRECISION - 1)
            else
                prob0[ctx] = math.max(prob0[ctx] - 1, 1)
            end
            ctx = (ctx * 2 + bit) % bit32.lshift(1, CTX_LEN)
        end,
    }
end

local function makeArithmeticEncoder(writeByte)
    local l, r = 0, 0xffffffff -- AC range segment
    return {
        encodeBit = function(bit, prob0)
            local mid = l + math.floor((r - l) * prob0 / PRECISION)
            if bit == 0 then
                r = mid
            else
                l = mid + 1
            end
            while bit32.rshift(l, 24) == bit32.rshift(r, 24) do
                writeByte(bit32.rshift(l, 24))
                l = bit32.lshift(l, 8)
                r = bit32.lshift(r, 8) + 0xff
            end
        end,
        finish = function()
            for _ = 1, 4 do
                writeByte(bit32.rshift(l, 24))
                l = bit32.lshift(l, 8)
            end
        end,
    }
end

local function makeArithmeticDecoder(readByte)
    local l, r = 0, 0 -- AC range segment
    local value = 0
    return {
        decodeBit = function(prob0)
            while bit32.rshift(l, 24) == bit32.rshift(r, 24) do
                l = bit32.lshift(l, 8)
                r = bit32.lshift(r, 8) + 0xff
                value = bit32.lshift(value, 8) + readByte()
            end
            local mid = l + math.floor((r - l) * prob0 / PRECISION)
            if value <= mid then
                r = mid
                return 0
            else
                l = mid + 1
                return 1
            end
        end,
    }
end

local function encode(input)
    local output = { string.byte("VOCZ" .. string.pack("<I", #input), 1, 8) }
    local output_len = 8

    local predictor = makePredictor()
    local ac = makeArithmeticEncoder(function(byte)
        output_len = output_len + 1
        output[output_len] = byte
    end)
    local prev_bit = 0

    for i = 1, #input do
        local byte = input:byte(i)
        for j = 0, 7 do
            local bit = bit32.rshift(byte, j) % 2
            local enc_bit = bit32.bxor(bit, prev_bit)
            ac.encodeBit(enc_bit, predictor.getProbability())
            predictor.feedBit(enc_bit)
            prev_bit = bit
        end
    end
    ac.finish()

    return string.char(table.unpack(output))
end

local function decode(input)
    assert(#input >= 12, "string too short")
    assert(input:sub(1, 4) == "VOCZ", "signature mismatch")
    local output_len = string.unpack("<I", input:sub(5, 8))
    local input_consumed = 8

    local predictor = makePredictor()
    local ac = makeArithmeticDecoder(function()
        input_consumed = input_consumed + 1
        return input:byte(input_consumed)
    end)
    local prev_bit = 0

    local output = {}
    for i = 1, output_len do
        local byte = 0
        for j = 0, 7 do
            local enc_bit = ac.decodeBit(predictor.getProbability())
            local bit = bit32.bxor(prev_bit, enc_bit)
            byte = byte + bit32.lshift(bit, j)
            predictor.feedBit(enc_bit)
            prev_bit = bit
        end
        output[i] = byte
    end

    return string.char(table.unpack(output))
end

return {
    encode = encode,
    decode = decode,
}
