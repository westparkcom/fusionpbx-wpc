--	Part of FusionPBX
--	Copyright (C) 2013 Mark J Crane <markjcrane@fusionpbx.com>
--	All rights reserved.
--
--	Redistribution and use in source and binary forms, with or without
--	modification, are permitted provided that the following conditions are met:
--
--	1. Redistributions of source code must retain the above copyright notice,
--	  this list of conditions and the following disclaimer.
--
--	2. Redistributions in binary form must reproduce the above copyright
--	  notice, this list of conditions and the following disclaimer in the
--	  documentation and/or other materials provided with the distribution.
--
--	THIS SOFTWARE IS PROVIDED ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES,
--	INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY
--	AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
--	AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY,
--	OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
--	SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
--	INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
--	CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
--	ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
--	POSSIBILITY OF SUCH DAMAGE.

--load libraries
	local send_mail = require 'resources.functions.send_mail'
	local Database = require "resources.functions.database"
	local Settings = require "resources.functions.lazy_settings"

	local toemail = argv[1]
	local recordingfile = argv[2]
	local dnis = argv[3]
	local caller_id_name = argv[4]
	local caller_id_number = argv[5]
	local message_date = argv[6]
	local message_time = argv[7]
	local domain_uuid = argv[8]
	local domain_name = argv[9]
	local splitrec = argv[10]
	local subjoverride = argv[11]
	local default_language = 'en'
	local default_dialect = 'us'
	local default_voice = 'callie'
	local stitchgap = "/usr/share/freeswitch/sounds/stitch_gap.wav"
	
--path split function
	function SplitFilename(strFilename)
		-- Returns the Path, Filename, and Extension as 3 values
		path, name, ext = string.match(strFilename, "(.-)([^/]-)%.([^/]+)$")
		return path, name
	end
--define a function to send email
	function send_email()
		local dbh = Database.new('system')
		local settings = Settings.new(db, domain_name, domain_uuid)
		local files = ''
		local finalfile = ''
		local finalname = ''
		local filepath = ''
		local deletemulti = false
		if splitrec then
			if splitrec == 'split' then
				for word in recordingfile:gmatch("[^:::]+") do
					files = files .. " " .. word
					files = files .. " " .. stitchgap
					filepath, finalname = SplitFilename(word)
				end
				deletemulti = true
				finalfile = filepath .. '/' .. finalname .. '-final.mp3'
			end
		else
			finalfile = recordingfile
		end
		if files ~= '' then
			local cmd = 'sox ' .. files .. ' -C 16.01 ' .. finalfile
			freeswitch.consoleLog('INFO', 'Executing command: `' .. cmd .. '`\n')
			local prog = os.execute(cmd)
		else
			finalfile = recordingfile
		end
		local cmd = "soxi -D " .. finalfile .. " 2>&1"
		local prog = io.popen(cmd)
		local lastline = ""
		for line in prog:lines() do
			lastline = line
		end
		freeswitch.consoleLog('INFO', 'Recording Length: `' .. lastline .. '`\n')
		local message_length_formatted = tostring(math.floor(tonumber(lastline))) .. " seconds"

		--get the templates
			
			local sql = "SELECT * FROM v_email_templates ";
			sql = sql .. "WHERE (domain_uuid = :domain_uuid or domain_uuid is null) ";
			sql = sql .. "AND template_language = :template_language ";
			sql = sql .. "AND template_category = 'recording' "
			sql = sql .. "AND template_enabled = 'true' "
			sql = sql .. "ORDER BY domain_uuid DESC "
			local params = {domain_uuid = domain_uuid, template_language = default_language.."-"..default_dialect};
			dbh:query(sql, params, function(row)
				subject = row["template_subject"];
				body = row["template_body"];
			end);
		--prepare the headers
			local headers = {
				["X-FusionPBX-Domain-UUID"] = domain_uuid;
				["X-FusionPBX-Domain-Name"] = domain_name;
				["X-FusionPBX-Call-UUID"]   = uuid;
				["X-FusionPBX-Email-Type"]  = 'recording';
			}

			--prepare the subject
				if subjoverride then
					subject = subjoverride
				end
				subject = subject:gsub("${caller_id_name}", caller_id_name);
				subject = subject:gsub("${caller_id_number}", caller_id_number);
				subject = subject:gsub("${message_date}", message_date .. " " .. message_time);
				subject = subject:gsub("${message_duration}", message_length_formatted);
				subject = subject:gsub("${domain_name}", domain_name);
				subject = trim(subject);
				subject = '=?utf-8?B?'..base64.encode(subject)..'?=';

			--prepare the body
				body = body:gsub("${caller_id_name}", caller_id_name);
				body = body:gsub("${caller_id_number}", caller_id_number);
				body = body:gsub("${message_date}", message_date .. " " .. message_time);
				body = body:gsub("${message_duration}", message_length_formatted);
				body = body:gsub("${domain_name}", domain_name);
				body = body:gsub("${dnis}", dnis);
				body = body:gsub("${message}", "Message is attached.");
				body = trim(body);

			-- Separate emails into comma list
				toemail = toemail:gsub(";", ',')
			--send the email
				send_mail(headers,
					toemail,
					{subject, body},
					finalfile
				);
			-- Remove the recording
				if deletemulti == true then
					os.remove(finalfile)
					for word in recordingfile:gmatch("[^:::]+") do
						os.remove(word)
					end
				end
	end
	
send_email()
