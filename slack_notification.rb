#!/usr/bin/env ruby
require 'net/http'
require 'uri'
require 'singleton'
require 'JSON'

# Slack Incoming Webhooks
# curl -X POST -H 'Content-type: application/json' --data '#{JSON}' __WEBHOOK_URL__

class Slack
  def initialize
    @uri = URI.parse(Slack::Webhook.instance.url)
  end

  def make_request(msg)
    request = Net::HTTP::Post.new(@uri)
    request["Content-type"] = "application/json"
    request.body = msg
    request
  end

  def send(msg)
    request = make_request(msg)
    response = Net::HTTP.start(@uri.hostname, @uri.port, use_ssl: @uri.scheme == "https") do |https|
      https.request(request)
    end
  end

  class Webhook
    include Singleton
  
    attr_reader :url
  
    def initialize  
      @url = load_url()
    end
  
    private
    def load_url
      `cat #{__dir__}/slack_webhook.url 2> /dev/null`.strip
    end
  
    public
    def check_url
      !(@url.nil? || @url.empty?)
    end
  end
end

# line = Slack.new
# msg = ARGV[0]

# res = Slack.send(msg)
# puts res.code
# puts res.body


class SlackNotification
  public
  def self.notify_launch(filter_id, version)
    url = URL.filter(filter_id)
    title = "이슈 알리아줌마: #{filter_id} 필터 확인을 시작합니다."
    message =
%(*이슈 알리아줌마* v#{version}
<#{url}|#{filter_id}> 필터 확인을 시작합니다.)

    res = Slack.new.send(JSON.generate({ text: title, blocks: [ section_for_text(message) ]}))
    res.code == "200"
  end

  def self.notify_termination(filter_id, version)
    url = URL.filter(filter_id)
    title = "이슈 알리아줌마: #{filter_id} 필터 확인을 종료합니다."
    message =
%(*이슈 알리아줌마* v#{version}
<#{url}|#{filter_id}> 필터 확인을 종료합니다.)

    res = Slack.new.send(JSON.generate({ text: title, blocks: [ section_for_text(message) ]}))
    res.code == "200"
  end

  def self.notify_issues_old(previous_issues, new_issues, updated_issues, filter_id)
    if new_issues.empty? && updated_issues.empty?
      return true
    end

    notify_new_issues(new_issues, filter_id) && notify_updated_issues(previous_issues, updated_issues, filter_id)
  end

  def self.section_for_text(text)
    {
      type: "section",
      text: {
        type: "mrkdwn",
        text: text
      }
    }
  end

  def self.notify_issues(previous_issues, new_issues, updated_issues, filter_id)
    if new_issues.empty? && updated_issues.empty?
      return true
    end

    header = "> :ladybug: *신규? #{new_issues.count}, 갱신 #{updated_issues.count}*"
    blocks = [ section_for_text(header) ]

    if not new_issues.empty?
      messages_from_new_issues(new_issues).map { |message|
        section_for_text(message)
      }.each { |section|
        blocks << section
      }
    end

    if not updated_issues.empty?
      messages_from_updated_issues(updated_issues, previous_issues).map { |message|
        section_for_text(message)
      }.each { |section|
        blocks << section
      }
    end

    title = "이슈 알리아줌마:\n 신규?(#{new_issues.count}), 갱신(#{updated_issues.count})"

    json = JSON.generate({ text: title, blocks: blocks })

    res = Slack.new.send(json)
    res.code == "200"

  end

  def self.messages_from_new_issues(new_issues)
    new_issues.each_with_index.map { |issue, index|
      key = issue[:key]
      summary = issue[:summary]
      status = issue[:status]
      
%(> *신규 이슈 (#{index+1}/#{new_issues.count}) *<#{URL.issue(key)}|#{key}>* _(#{status})_
> #{summary})
    }
  end

  def self.messages_from_updated_issues(updated_issues, previous_issues)
    updated_issues.each_with_index.map { |issue, index|
      key = issue[:key]
      not_found = issue[:not_found]

      if not_found
        error_messages = issue[:error_messages].join(',')
%(> *갱신 이슈 (#{index+1}/#{updated_issues.count}) <#{URL.issue(key)}|#{key}>*
> 이슈 정보를 찾을 수 없습니다 (#{error_messages}))
      else
        summary = issue[:summary]
        status = issue[:status]

        previous_issue = previous_issues.find {|prev_issue| prev_issue[:key] == key }
        
        new_changes = new_changes_of_updated_issue(issue, previous_issue)
          .map {|change| message_from_change(change) }
          
        new_comments = new_comments_of_updated_issue(issue, previous_issue)
          .map {|comment| message_from_comment(comment) }

        next nil if new_comments.empty? and new_changes.empty?

        message = %(> *갱신 이슈(#{index+1}/#{updated_issues.count}) <#{URL.issue(key)}|#{key}>* _(#{status})_
> #{summary})

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
    .compact
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

      message = %(- _#{who}_ 님이 _#{what}_ 를 _#{action}_ : )
      
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
