#!/usr/bin/env ruby

class OSXNotification
	public
	def self.notify_launch(filter_id, version)
		notify(title: "JIRA 확인 시작(#{version})",
			message: "#{filter_id} 필터 확인을 시작합니다",
			url: URL.filter(filter_id))
	end

	def self.notify_termination(filter_id, version)
		notify(title: "JIRA 확인 종료(#{version})", message: "#{filter_id} 필터 확인이 종료되었습니다. 직접 종료하지 않은 경우 로그를 확인해 주세요.", url: URL.filter(filter_id))	
	end

	def self.notify_issues(previous_issues, new_issues, updated_issues, filter_id)
		if new_issues.empty? && updated_issues.empty?
			return
		end

		only_new_issues = !new_issues.empty? && updated_issues.empty?
		only_updated_issues = new_issues.empty? && !updated_issues.empty?

		if only_new_issues
			notify_new_issues(new_issues, filter_id)
		elsif only_updated_issues
			notify_updated_issues(previous_issues, updated_issues, filter_id)
		else
			notify_all_issues(previous_issues, new_issues, updated_issues, filter_id)
		end
	end
	
	private
	def self.notify(title:, subtitle: "", message:, url:)
		# terminal-notifier --help
		# 
		# ```
		# Note that in some circumstances the first character of a message has to be escaped in order to be recognized.
		# An example of this is when using an open bracket, which has to be escaped like so: ‘\[’.	
		# ```
		#`terminal-notifier -title "#{title}" -subtitle "#{subtitle}" -message "\\#{message}" -execute "#{execution}"`

		`terminal-notifier -sound default -title "#{title}" -subtitle "#{subtitle}" -message "\\#{message}" -open "#{url}"`
	end
	
	def self.notify_new_issues(new_issues, filter_id)
		if new_issues.count == 1
			issue = new_issues.first

			key = issue[:key]
			summary = issue[:summary]
			status = issue[:status]

			notify(title: "신규? 이슈 (#{key})", subtitle: status, message: summary, url: URL.issue(key))
		else
			message = new_issues.map { |issue|
				key = issue[:key] 
				status = issue[:status] 
				"#{key}(#{status})"
			}
			
			notify(title: "신규? 이슈 (#{new_issues.count})", message: message.join(','), url: URL.filter(filter_id))
		end
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
				previous_issue_updated_i <= change_created_i
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
				previous_issue_updated_i <= comment_updated_i
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

			message = %(#{who}님이 [#{what}]를 변경: )
			
			message += from ? from: ""
			message += " -> " if !from.nil? && !to.nil?
			message += to ? to: ""
		}
	end

	def self.message_from_comment(comment)
		who = comment[:who]
		comment = comment[:comment]

		%(#{who}님이 작성: #{comment})
	end
	
	def self.messages_from_updated_issues(updated_issues, previous_issues)
		updated_issues.map { |issue|
			key = issue[:key]
			not_found = issue[:not_found]

			if not_found
				error_messages = issue[:error_messages].join(',')
				%(#{key} 이슈 정보를 찾을 수 없습니다 (#{error_messages}))
			else
				previous_issue = previous_issues.find {|prev_issue| prev_issue[:key] == key }

				new_changes = new_changes_of_updated_issue(issue, previous_issue)
					.map {|change| message_from_change(change) }
					
				new_comments = new_comments_of_updated_issue(issue, previous_issue)
					.map {|comment| message_from_comment(comment) }

				new_changes + new_comments
			end
		}
	end

	def self.notify_updated_issues(previous_issues, updated_issues, filter_id)
		if updated_issues.count == 1
			issue = updated_issues.first
			key = issue[:key]
			status = issue[:status]

			message = messages_from_updated_issues(updated_issues, previous_issues).join(',')

			notify(title: "이슈 갱신 (#{key})", subtitle: status, message: message, url: URL.issue(key))
		else
			message = updated_issues.map { |issue|
				key = issue[:key] 
				status = issue[:status] 
				"#{key}(#{status})"
			}

			notify(title: "이슈 갱신 (#{updated_issues.count})", message: message.join(','), url: URL.filter(filter_id))
		end
	end

	def self.notify_all_issues(previous_issues, new_issues, updated_issues, filter_id)
		title = "신규? 이슈(#{new_issues.count}) / 갱신 이슈(#{updated_issues.count})"

		new_keys = new_issues.map { |issue| "#{issue[:key]}(#{issue[:status]})" }
		updated_keys = updated_issues.map { |issue| "#{issue[:key]}(#{issue[:status]})" }

		message = (new_keys + updated_keys).join(',')

		notify(title: title, message: message, url: URL.filter(filter_id))
	end
end