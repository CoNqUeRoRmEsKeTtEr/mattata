--[[
    Copyright 2020 Matthew Hesketh <matthew@matthewhesketh.com>
    This code is licensed under the MIT. See LICENSE for details.
]]

local fwhitelist = {}
local mattata = require('mattata')
local redis = require('libs.redis')

function fwhitelist:init()
    fwhitelist.commands = mattata.commands(self.info.username):command('fwhitelist'):command('fedban'):command('fb').table
    fwhitelist.help = '/fwhitelist [user] - Whitelists a user from the current chat\'s Feds. Only works per chat, not per fed. This command can only be used by Fed admins. Alias: /fw.'
end

function fwhitelist:on_message(message, configuration, language)
    if message.chat.type ~= 'supergroup' then
        local output = language['errors']['supergroup']
        return mattata.send_reply(message, output)
    end
    local fed_ids = mattata.get_feds(message.chat.id)
    if #fed_ids == 0 then
        return mattata.send_reply(message, 'This group isn\'t part of a fed. Ask a group admin to join one!')
    end
    local user = message.reply and message.reply.from.id or mattata.input(message.text)
    if not user then
        local output = 'You need to specify the user you\'d like to whitelist from the Fed, either by username/ID or in reply.'
        local success = mattata.send_force_reply(message, output)
        if success then
            mattata.set_command_action(message.chat.id, success.result.message_id, '/fwhitelist')
        end
        return
    end
    if tonumber(user) == nil and not user:match('^%@') then
        user = '@' .. user
    end
    local user_object = mattata.get_user(user) -- resolve the username/ID to a user object
    if not user_object then
        local output = language['errors']['unknown']
        return mattata.send_reply(message, output)
    elseif user_object.result.id == self.info.id then
        return false -- don't let the bot Fed-whitelist itself
    end
    user_object = user_object.result
    local status = mattata.get_chat_member(message.chat.id, user_object.id)
    local is_admin = mattata.is_group_admin(message.chat.id, user_object.id)
    if not status then
        local output = language['errors']['generic']
        return mattata.send_reply(message, output)
    elseif is_admin or status.result.status == ('creator' or 'administrator') then -- we won't try and Fed-whitelist moderators and administrators.
        local output = 'I can\'t whitelist that user from the Fed because they\'re an admin in one of the groups!'
        return mattata.send_reply(message, output)
    end
    mattata.fed_whitelist(message.chat.id, user_object.id)
    if mattata.get_setting(message.chat.id, 'log administrative actions') then
        local log_chat = mattata.get_log_chat(message.chat.id)
        local admin_username = mattata.get_formatted_user(message.from.id, message.from.first_name, 'html')
        local whitelisted_username = mattata.get_formatted_user(user_object.id, user_object.first_name, 'html')
        local output = '%s <code>[%s]</code> has Fed-whitelisted %s <code>[%s]</code> from %s <code>[%s]</code>.'
        if #fed_ids > 1 then
            output = '%s <code>[%s]</code> has Fed-whitelisted %s <code>[%s]</code> from %s in the following Feds:<pre>%s</pre>'
            output = string.format(output, admin_username, message.from.id, whitelisted_username, user_object.id, mattata.escape_html(message.chat.title), table.concat(fed_ids, '\n'))
        else
            output = string.format(output, admin_username, message.from.id, whitelisted_username, user_object.id, mattata.escape_html(message.chat.title), message.chat.id)
        end
        mattata.send_message(message.chat.id, output, 'html')
    end
    if message.reply and mattata.get_setting(message.chat.id, 'delete reply on action') then
        mattata.delete_message(message.chat.id, message.reply.message_id)
    end
    local admin_username = mattata.get_formatted_user(message.from.id, message.from.first_name, 'html')
    local whitelisted_username = mattata.get_formatted_user(user_object.id, user_object.first_name, 'html')
    local output = '%s has Fed-whitelisted %s.'
    if #fed_ids > 1 then
        output = '%s has Fed-whitelisted %s; in the following Feds:<pre>%s</pre>'
        output = string.format(output, admin_username, whitelisted_username, table.concat(fed_ids, '\n'))
    else
        output = string.format(output, admin_username, whitelisted_username)
    end
    return mattata.send_message(message.chat.id, output, 'html')
end

return fwhitelist