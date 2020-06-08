#!/usr/bin/env ruby

require 'daemons'

def search_fileter_id_for_pid(pid)
    tags = Dir.entries(__dir__)
    .select { |entry| entry.start_with?(".") && entry.end_with?(".filter") }
    .map { |entry|
        pid = /\d+/.match(entry).to_s
        filter_id = `cat #{__dir__}/#{entry}`.strip
        [ pid, filter_id ]
    }
    .to_h

    tags[pid]
end

def custom_show_status(app)
    pid = app.pid.pid.to_s
    filter_id = search_fileter_id_for_pid(pid)

    puts "PID: #{pid}, FILTER ID: #{filter_id}"
end

Daemons.run("#{__dir__}/_jira.rb", { app_name: 'jira-notification', multiple: true, show_status_callback: :custom_show_status })