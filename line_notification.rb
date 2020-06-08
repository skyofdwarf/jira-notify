#!/usr/bin/env ruby
require 'net/http'
require 'uri'
require 'singleton'

class Line
  URI = URI.parse("https://notify-api.line.me/api/notify")

  def initialize
    Line::Account.instance.token
  end

  def make_request(msg)
    request = Net::HTTP::Post.new(URI)
    request["Authorization"] = "Bearer #{Line::Account.instance.token}"
    request.set_form_data(message: msg)
    request
  end

  def send(msg)
    request = make_request(msg)
    response = Net::HTTP.start(URI.hostname, URI.port, use_ssl: URI.scheme == "https") do |https|
      https.request(request)
    end
  end

  class Account
    include Singleton
  
    attr_reader :token
  
    def initialize	
      @token = load_token()
    end
  
    private
    def load_token
      `cat #{__dir__}/line.token 2> /dev/null`.strip
    end
  
    public
    def check_token
      !(@token.nil? || @token.empty?)
    end
  end
end

# line = Line.new
# msg = ARGV[0]

# res = line.send(msg)
# puts res.code
# puts res.body


class LineNotification
  public
  def self.notify_launch(filter_id, version)
    res = notify(title: "*JIRA 확인 시작* _(#{version})_", message: "*#{filter_id}* 필터 확인을 시작합니다", url: URL.filter(filter_id))
    return res.code == "200"
  end

  def self.notify_termination(filter_id, version)
    res = notify(title: "*JIRA 확인 종료* _(#{version})_", message: "*#{filter_id}*  필터 확인이 종료되었습니다. 직접 종료하지 않은 경우 로그를 확인해 주세요.", url: URL.filter(filter_id))
    return res.code == "200"
  end

  def self.notify_issues(previous_issues, new_issues, updated_issues, filter_id)
    if new_issues.empty? && updated_issues.empty?
      return true
    end

    notify_new_issues(new_issues, filter_id) && notify_updated_issues(previous_issues, updated_issues, filter_id)
  end

  private
  def self.notify(title:, message:, url:)
    line_message =
%(#{title}
#{url}
#{message})

    Line.new.send(line_message)
  end

  def self.notify_new_issues(new_issues, filter_id)
    return true if new_issues.empty?

    new_messages = messages_from_new_issues(new_issues)

    line_message = 
%(*신규? 이슈(#{new_issues.count})*

#{new_messages.join("\n\n")})

    res = Line.new.send(line_message)
    res.code == "200"
  end

  def self.notify_updated_issues(previous_issues, updated_issues, filter_id)
    return true if updated_issues.empty?

    updated_messages = messages_from_updated_issues(updated_issues, previous_issues)
    total_message_count = updated_messages.count

    results = []

    updated_messages.each_with_index {|message, index|
      title = ""
      line_message = %(*갱신 이슈(#{index+1}/#{updated_messages.count})*

#{message})
      res = Line.new.send(line_message)
      results << res.code == "200"

      sleep(0.2)
    }

    results.all?
  end

  def self.messages_from_new_issues(new_issues)
    new_issues.map { |issue|
      key = issue[:key]
      summary = issue[:summary]
      status = issue[:status]
      
%(*#{key}* _(#{status})_
#{URL.issue(key)}
#{summary})
    }
  end
  
  def self.messages_from_updated_issues(updated_issues, previous_issues)
    updated_issues.map { |issue|
			key = issue[:key]
			not_found = issue[:not_found]

			if not_found
        error_messages = issue[:error_messages].join(',')
%(*#{key}*
#{URL.issue(key)}
이슈 정보를 찾을 수 없습니다 (#{error_messages}))
      else
        summary = issue[:summary]
        status = issue[:status]

        previous_issue = previous_issues.find {|prev_issue| prev_issue[:key] == key }
        
        new_changes = new_changes_of_updated_issue(issue, previous_issue)
          .map {|change| message_from_change(change) }
					
				new_comments = new_comments_of_updated_issue(issue, previous_issue)
          .map {|comment| message_from_comment(comment) }
        
        message = %(*#{key}* _(#{status})_
#{URL.issue(key)}
#{summary})

        if !new_changes.empty?
          message += %(
*변경 사항*
#{new_changes.join("\n")})
        end

        if !new_comments.empty?
          message += %(
*코멘트*
#{new_comments.join("\n")})
        end

        message
      end
    }
  end

  def self.new_changes_of_updated_issue(updated_issue, previous_issue)
		changes = updated_issue[:changes]

		if previous_issue.nil?
			changes.last ? changes.last: []
		else
			previous_issue_updated = previous_issue[:updated]

			changes.select { |change|
				change_created = change[:created]

				change_created_i = DateTime.parse(change_created).to_time.to_i
				previous_issue_updated_i = DateTime.parse(previous_issue_updated).to_time.to_i
				previous_issue_updated_i < change_created_i
			}
		end
	end

	def self.new_comments_of_updated_issue(updated_issue, previous_issue)
		comments = updated_issue[:comments]

		if previous_issue.nil?
			changes.last ? changes.last: []
		else
			previous_issue_updated = previous_issue[:updated]

			comments.select { |comment|
				comment_updated = comment[:updated]

				comment_updated_i = DateTime.parse(comment_updated).to_time.to_i
				previous_issue_updated_i = DateTime.parse(previous_issue_updated).to_time.to_i
				previous_issue_updated_i < comment_updated_i
			}
		end
	end

	def self.message_from_change(change)
		who = change[:who]
		changed = change[:changed]

		changed.map {|item|
			what = item[:what]
			from = item[:from]
			to = item[:to]

      from = from ? from: ""
      to = to ? to: ""
      
      added = from.empty? && !to.empty?
      deleted = !from.empty? && to.empty?
      
      action = added ? "추가": (deleted ? "삭제": "변경")

      message = %(_#{who}_ 님이 _#{what}_ 를 _#{action}_ : )
      
      if what.downcase.start_with?("description")
        message += "_JIRA 에서 확인 해 주세요_"
      else
        if added
          message += "`#{to}`"
        elsif deleted
          message += "~#{from}~"
        else
          message += "~#{from}~ -> `#{to}`"
        end
      end
		}
	end

	def self.message_from_comment(comment)
		who = comment[:who]
		comment = comment[:comment]

		%(_#{who}_ 님이 작성: ```#{comment}```)
	end
end