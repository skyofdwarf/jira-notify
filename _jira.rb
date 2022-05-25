#!/usr/bin/env ruby

require "uri"
require "net/http"
require 'json'
require 'pp'
require 'date'
require 'singleton'
require 'base64'
require "#{__dir__}/line_notification"
require "#{__dir__}/osx_notification"

=begin
CHANGELOG

* 1.2.1
	- changelog.histories `RemoteIssueLink` 필드 아이템은 알림 제외(문서 편집시 마다 알림폭탄이 쏟아짐)
* 1.2.0
	- 라인 메시지의 변경 사항 표시 수정
* 1.1.0
	- 갱신 이슈의 변경사항/코멘트에 지난 항목이 포함되는 문제 수정
	- setup파일에 daemns 설치 추가
* 1.0.0
	- 첫 정식 릴리즈
=end

APP_VERSION = "1.2.0"

module Defaults
	public
	BROWSER = "Safari"
	MAX_RESULT_COUNT = 100
	POLLING_PERIOD = 300 # 5 mins

	module Backup
		def self.filepath(filter_id)
			"#{__dir__}/.jira-#{filter_id}.json"
		end

		def self.tag
			"#{__dir__}/.#{Process.pid}.filter"
		end
	end
end

module URL
	private
	BASE = "__JIRA_BASE_URL__"
	ISSUE = "/browse/"
	FILTER = "/issues/?filter="

	public	
	def self.issue(key)
		"#{BASE}#{ISSUE}#{key}"
	end

	def self.filter(filter_id)
		"#{BASE}#{FILTER}#{filter_id}"
	end
end

module URL
	module API
		private
		API_BASE = "__JIRA_BASE_URL__"
		API_FILTER = "/rest/api/2/filter"
		API_SEARCH = "/rest/api/2/search"
		API_ISSUE = "/rest/api/2/issue"

		public
		def self.uri
			URI(API_BASE)
		end

		def self.filter(filter_id)
			"#{API_FILTER}/#{filter_id}"
		end

		def self.search
			API_SEARCH
		end

		def self.issue(key)
			"#{API_ISSUE}/#{key}?fields=status,created,updated,summary,comment&updateHistory=false&expand=changelog"
		end
	end
end

def http_request(method, path, body="")
	uri = URL::API.uri

	https = Net::HTTP.new(uri.host, uri.port)
	https.use_ssl = true
	
	headers = {
		"Authorization" => "Basic #{Account.instance.authorization}",
		"Content-Type" => "application/json"
	}

	case method
	when :get
		response = https.request_get(path, headers)
	when :post
		response = https.request_post(path, body, headers)
	else
		riase "Not supported http method: #{method}"
	end
	
	JSON.parse(response.body, symbolize_names: true)
end


def get_filter(filter_id)
	http_request(:get, URL::API.filter(filter_id))
end

def search(jql, max_result)
	body = %({
		"jql": "#{jql}",
	    "startAt": 0,
	    "maxResults": #{max_result},
	    "fields": [
	    	"components",
	    	"assignee",
	        "summary",
	        "created",
			"updated",
			"status"
	    ]
	})

	http_request(:post, URL::API.search, body)
end

def get_issue(key)
	http_request(:get, URL::API.issue(key))
end

def fetch_issues(filter_id, max_result)
	filter_response = get_filter(filter_id)

	filter_jql = filter_response[:jql].gsub('"', '\\\"')

	search_result = search(filter_jql, max_result)

	search_result[:issues].map { |issue|
		key = issue[:key]
		fields = issue[:fields]

		summary = fields[:summary]
		updated = fields[:updated]
		created = fields[:created]
		status = fields[:status][:name]

		{ key: key, summary: summary, updated: updated, created: created, status: status }
	}
end

def mock_fetch_issues(filter_id, max_result)
	mock_jsonpath = "#{__dir__}/mock-#{filter_id}.json"
	json = JSON.parse(File.read(mock_jsonpath), symbolize_names: true)

	json.map { |issue|
		key = issue[:key]
		summary = issue[:summary]
		updated = issue[:updated]
		created = issue[:created]
		status = issue[:status]

		{ key: key, summary: summary, updated: updated, created: created, status: status }
	}
end

def get_issue_status(key)
	issue_response = get_issue(key)
	
	if issue_response.has_key?(:errorMessages)
		error_messages = issue_response[:errorMessages]
		return { key: key, error_messages: error_messages, not_found: true }
	end

	histories = issue_response[:changelog][:histories]
	fields = issue_response[:fields]
	
	status = fields[:status][:name]

	created = fields[:created]
	updated = fields[:updated]
	summary = fields[:summary]
	comments = fields[:comment][:comments]

	comments = comments.map { |comment|
		comment_updated = comment[:updated]
		name = comment[:author][:displayName]
		body = comment[:body]
		
		{ updated: comment_updated, who: name, comment: body }
	}
	
	changes = histories.map { |history|
		history_created = history[:created]
		name = history[:author][:displayName]
		changed = history[:items]
			.map { |item| { what: item[:field], from: item[:fromString], to: item[:toString] } }
			.select { |item| item[:what].downcase != 'RemoteIssueLink'.downcase }

		{ created: history_created, who: name, changed: changed }
	}

	{ key: key, summary: summary, updated: updated, created: created, status: status, comments: comments, changes: changes, not_found: false } 
end

def mock_get_issue_status(key)
	#{ key: key, error_messages: ["error message 1"], , not_found: true }
	{ key: key, summary: "summary", updated: Time.now.to_s, created: Time.now.to_s, status: "상태 메롱", comments: [], changes: [], not_found: false } 
end

def notify_launch(filter_id)
	unless LineNotification.notify_launch(filter_id, APP_VERSION)
		OSXNotification.notify_launch(filter_id, APP_VERSION)
	end
end

def notify_termination()
	filter_id = Config.instance.filter_id

	unless LineNotification.notify_termination(filter_id, APP_VERSION)
		OSXNotification.notify_termination(filter_id, APP_VERSION)
	end
end

def notify_issues(previous_issues, new_issues, updated_issues, filter_id)
	if new_issues.empty? && updated_issues.empty?
		return
	end

	unless LineNotification.notify_issues(previous_issues, new_issues, updated_issues, filter_id)
		OSXNotification.notify_issues(previous_issues, new_issues, updated_issues, filter_id)
	end
end

def load_data(filter_id)
	filepath = Defaults::Backup.filepath(filter_id)
	JSON.parse(File.read(filepath), symbolize_names: true)
rescue
	# No backup data
	[]
end

def save_data(filter_id, json)
	filepath = Defaults::Backup.filepath(filter_id)
	IO.write(filepath, JSON.pretty_generate(json))

	log "Saved to #{filepath}"
rescue
	[]
end

def mock_save_data(filter_id, json)
	# do nothing
end

def find_appeared_issues(previous_issues, current_issues)
	current_keys = current_issues.map { |issue| issue[:key] }
	previous_keys = previous_issues.map { |issue| issue[:key] }

	new_keys = current_keys.select { |curent_key| !previous_keys.include? curent_key }

	new_issues = current_issues.select { |issue| new_keys.include?(issue[:key]) }

	return new_issues
end

def find_disappeared_issues(previous_issues, current_issues)
	current_keys = current_issues.map { |issue| issue[:key] }
	previous_keys = previous_issues.map { |issue| issue[:key] }

	disappeared_keys = previous_keys.select { |previous_key| !current_keys.include? previous_key }

	previous_disappeared_issues = previous_issues.select { |issue| disappeared_keys.include? issue[:key] }

	return previous_disappeared_issues
end

def find_same_issues(previous_issues, current_issues)
	current_keys = current_issues.map { |issue| issue[:key] }
	previous_keys = previous_issues.map { |issue| issue[:key] }

	same_keys = current_keys.select { |curent_key| previous_keys.include? curent_key }

	current_same_issues = current_issues
		.select { |issue| same_keys.include? issue[:key] }
		.sort { |l,r| l[:key] <=> r[:key] }

	previous_same_issues = previous_issues
		.select { |issue| same_keys.include? issue[:key] }
		.sort { |l,r| l[:key] <=> r[:key] }

	return previous_same_issues.zip(current_same_issues)
end

def find_changes_from_issues(previous_issues, current_issues)
	# (maybe)new issues
	appeared_issues = find_appeared_issues(previous_issues, current_issues)
	
	maybe_new_issues = appeared_issues.select { |issue|
		one_week_ago = (Time.now - (7 * 86400)).to_i
		issue_created = DateTime.parse(issue[:created]).to_time.to_i
		issue_created > one_week_ago
	}

	# updated
	disappeared_prev_issues = find_disappeared_issues(previous_issues, current_issues)
	disappeared_issues = disappeared_prev_issues
		.map { |issue| issue[:key] }
		.map { |key|
			#mock_get_issue_status(key)
			get_issue_status(key)
		}

	disappeared_updated_issues = disappeared_prev_issues.zip(disappeared_issues)
		.select { |(p, c)|
			if c[:not_found]
				true
			else
				previous_updated = DateTime.parse(p[:updated]).to_time.to_i
				current_updated = DateTime.parse(c[:updated]).to_time.to_i
				previous_updated < current_updated
			end
		}
		.map { |(p,c)| c }

	same_issues = find_same_issues(previous_issues, current_issues)
	updated_issues = same_issues
		.select { |(p, c)|
			previous_updated = DateTime.parse(p[:updated]).to_time.to_i
			current_updated = DateTime.parse(c[:updated]).to_time.to_i
			previous_updated < current_updated
		}
		.map { |(p,c)| c[:key] }
		.map { |key|
			#mock_get_issue_status(key)
			get_issue_status(key)
		}
		.select { |issue| !issue[:changes].empty? }
		

	{ new_issues: maybe_new_issues, updated_issues: disappeared_updated_issues + updated_issues }
end

def log(what, tag=Config.instance.filter_id)
	time = Time.now.strftime "%Y-%m-%d %H:%M:%S"
	puts "[#{time}][#{tag}] #{what}"
end

# Account
class Account
	include Singleton

	attr_reader :authorization

	def initialize	
		load_account()
	end

	private
	def load_account
		account = `cat #{__dir__}/jira.account 2> /dev/null`.strip
		@authorization = Base64.encode64(account) if !(account.nil? || account.empty?)
	end

	public
	def check_account
		!(@authorization.nil? || @authorization.empty?)
	end
end

# Config
class Config
	include Singleton

	attr_reader :filter_id, :polling_period, :browser, :max_result

	def initialize	
		@max_result = Defaults::MAX_RESULT_COUNT
	end

	private
	def is_test_mode?(argv)
		argv.count > 3 && argv.last == "test"
	end
	
	def get_filter_id(argv)
		argv[0] if argv.count > 0
	end
	
	def get_polling_period(argv)
		if argv.count > 1
			user_period = argv[1].to_i
	
			if is_test_mode?(argv)
				log "Test polling period: #{user_period}"
				return user_period
			end
	
			if user_period < Defaults::POLLING_PERIOD
				log "User polling period: #{user_period}"
				log "Minimum polling period is #{Defaults::POLLING_PERIOD}"
			end
			return [ user_period, Defaults::POLLING_PERIOD ].max
		else
			return Defaults::POLLING_PERIOD
		end
	end
	
	def get_browser(argv)
		argv.count > 2 ? argv[2]: Defaults::BROWSER
	end
	
	public
	def check_arguments(argv)
		@filter_id = get_filter_id(argv)
		@polling_period = get_polling_period(argv)
		@browser = get_browser(argv)

		return !(@filter_id.nil?|| @filter_id.empty?)
	end

	def to_s
		"Filter ID: #{@filter_id}, Polling period: #{@polling_period}(s), Browser: #{@browser}"
	end
end

class App
	include Singleton

	def run(config)
		polling_period = config.polling_period
		filter_id = config.filter_id
		previous_issues = load_data(filter_id)

		notify_launch(filter_id)
	
		loop do
			begin
				previous_issues = process(config, previous_issues)
			rescue SocketError,
				# REF: http://tammersaleh.com/posts/rescuing-net-http-exceptions/
				Timeout::Error, Errno::EINVAL, Errno::ECONNRESET, EOFError,
				Errno::EHOSTUNREACH, Errno::ETIMEDOUT, Errno::ENETUNREACH,
				Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError, Net::ProtocolError => e
				log  "Network Exception: #{e}"
			 end
			
			log  "Step's done. Next step is after #{polling_period} seconds.\n"
	
			sleep(polling_period)
		end
	end

	private
	def process(config, previous_issues)
		filter_id = config.filter_id
		#browser = config.browser
		max_result = config.max_result

		saves_data = true
			
		current_issues = fetch_issues(filter_id, max_result)
		#current_issues = mock_fetch_issues(filter_id, max_result)

		if previous_issues.empty?
			log "No saved data"
		else
			changed_issues = find_changes_from_issues(previous_issues, current_issues)
			new_issues = changed_issues[:new_issues]
			updated_issues = changed_issues[:updated_issues]

			saves_data = !(new_issues.empty? && updated_issues.empty?)

			notify_issues(previous_issues, new_issues, updated_issues, filter_id)

			log "New issues: #{new_issues.count}" unless new_issues.empty?
			log "Updated issues: #{updated_issues.count}" unless updated_issues.empty?
		end
	
		if saves_data
			save_data(filter_id, current_issues)
			#mock_save_data(filter_id, previous_issues)
		end

		current_issues
	end
end

def create_tag_file
	filter_id = Config.instance.filter_id
	tagfile_path = Defaults::Backup.tag()
	`echo #{filter_id} > #{tagfile_path}`
	
	log "Tag file created(#{$?.exitstatus}): #{tagfile_path}"
end

def remove_tag_file
	tagfile_path = Defaults::Backup.tag()
	`rm #{tagfile_path} 2> /dev/null`

	log "Tag file removed(#{$?.exitstatus}): #{tagfile_path}"
end

at_exit {
	notify_termination()
	remove_tag_file()

	log  "Exited"
}

Signal.trap("TERM") {
	log  "Received signal 'TERM'"
	
	#notify_termination()
	exit
}

Signal.trap("INT") {
	log  "Received signal 'INT'"
	
	#notify_termination()
	exit
}

unless Config.instance.check_arguments(ARGV)
	log "Invalid arguments: '#{ARGV.join}'"
	exit
end

unless Account.instance.check_account()
	log "No account: save account to jira.account with format `id:pw`"
	exit
end

# start

log "PID: #{Process.pid}"
log "Configuration: #{Config.instance}"

create_tag_file()
App.instance.run(Config.instance)
