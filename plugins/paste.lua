--[[
    Copyright 2020 Matthew Hesketh <matthew@matthewhesketh.com>
    This code is licensed under the MIT. See LICENSE for details.
]]

local paste = {}
local mattata = require('mattata')
local https = require('ssl.https')
local http = require('socket.http')
local url = require('socket.url')
local ltn12 = require('ltn12')
local mime = require('mime')
local multipart = require('multipart-post')
local json = require('dkjson')
local configuration = require('configuration')
local redis = require('libs.redis')

function paste:init()
    paste.commands = mattata.commands(self.info.username):command('paste').table
    paste.help = '/paste <text> - Uploads the given text, or replied-to text to a pasting service and returns the result URL.'
end

function paste.get_keyboard(current_time)
    current_time = current_time or 0
    return mattata.inline_keyboard()
    :row(
        mattata.row()
        :callback_data_button(
            'paste.ee',
            'paste:pasteee:' .. current_time
        )
        :callback_data_button(
            'pastebin.com',
            'paste:pastebin:' .. current_time
        )
        :callback_data_button(
            'hastebin.com',
            'paste:hastebin:' .. current_time
        )
    )
end

function paste.pasteee(input, id)
    input = '{"description":"' .. id .. ' via mattata","sections":[{"name":"Paste","syntax":"autodetect","contents":"' .. url.escape(input) .. '"}]}'
    local response = {}
    local _, res = https.request(
        {
            ['url'] = 'https://api.paste.ee/v1/pastes',
            ['method'] = 'POST',
            ['headers'] = {
                ['Content-Type'] = 'application/json',
                ['Content-Length'] = input:len(),
                ['Authorization'] = 'Basic ' .. mime.b64(configuration.keys.pasteee .. ':')
            },
            ['source'] = ltn12.source.string(input),
            ['sink'] = ltn12.sink.table(response)
        }
    )
    if res ~= 201 then
        return false
    end
    local jstr = table.concat(response)
    local jdat = json.decode(jstr)
    if not jdat or not jdat.success then
        return false
    end
    return jdat.link
end

function paste.pastebin(input)
    local parameters = {
        ['api_dev_key'] = configuration.keys.pastebin,
        ['api_option'] = 'paste',
        ['api_paste_code'] = input
    }
    local response = {}
    local body, boundary = multipart.encode(parameters)
    local _, res = http.request(
        {
            ['url'] = 'http://pastebin.com/api/api_post.php',
            ['method'] = 'POST',
            ['headers'] = {
                ['Content-Type'] = 'multipart/form-data; boundary=' .. boundary,
                ['Content-Length'] = #body
            },
            ['source'] = ltn12.source.string(body),
            ['sink'] = ltn12.sink.table(response)
        }
    )
    if res ~= 200
    then
        return false
    end
    return table.concat(response)
end

function paste.hastebin(input)
    local parameters = {
        ['data'] = input
    }
    local response = {}
    local body, boundary = multipart.encode(parameters)
    local _, res, head = https.request(
        {
            ['url'] = 'https://hasteb.in/documents',
            ['method'] = 'POST',
            ['headers'] = {
                ['Content-Type'] = 'multipart/form-data; boundary=' .. boundary,
                ['Content-Length'] = #body
            },
            ['redirect'] = false,
            ['source'] = ltn12.source.string(body),
            ['sink'] = ltn12.sink.table(response)
        }
    )
    if res ~= 200
    then
        return false
    end
    local jdat = json.decode(table.concat(response))
    if not jdat
    or not jdat.key
    then
        return false
    end
    return 'https://hasteb.in/' .. jdat.key
end

function paste:on_callback_query(callback_query, message, configuration, language)
    local input = mattata.input(message.reply.text)
    if not input then
        input = redis:get('paste:' .. callback_query.data:match(':(%d+)$'))
        redis:del('paste:' .. callback_query.data:match(':(%d+)$'))
        callback_query.data = callback_query.data:match('^(%a+):')
    end
    local output
    if callback_query.data == 'pasteee' then
        output = paste.pasteee(input, callback_query.from.id)
    elseif callback_query.data == 'pastebin' then
        output = paste.pastebin(input)
    elseif callback_query.data == 'hastebin' then
        output = paste.hastebin(input)
    end
    if not output then
        return mattata.answer_callback_query(callback_query.id, language['errors']['generic'])
    end
    return mattata.edit_message_text(message.chat.id, message.message_id, output, nil, true, paste.get_keyboard())
end

function paste:on_message(message, configuration, language)
    local current_time = os.time()
    local input = message.reply and message.reply.text or mattata.input(message.text)
    if not input then
        return mattata.send_reply(message, paste.help)
    elseif message.reply then
        redis:set('paste:' .. current_time, input)
    end
    return mattata.send_message(message.chat.id, language['paste']['1'], nil, true, false, message.message_id, paste.get_keyboard(message.reply and current_time or false))
end

return paste