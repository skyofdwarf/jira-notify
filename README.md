# jira-notify
Simple JIRA issue notifier for macOS

새/갱신된 JIRA 이슈들을 알려주는 Ruby 스크립트

JIRA에 등록된 이슈 filter를 이용하며, n분마다 폴링해 새/갱신 이슈를 알림준다.

macOS환경에 동작하고 `setup`파일을 실행하기 위해 ruby, brew등이 설치되어 있어야 한다.



## 알림 종류

* 슬랙
  
  webhook url을 가지는 `slack_webhook.url` 파일 생성

* 라인
  
  토큰값을 가지는 `line.token` 파일 생성

* macOS 알림
  
  슬랙, 라인 없는 경우 macOS의 노티로 알림
  
> 슬랙 -> 라인 -> 맥노티 우선순위로 가능한 1가지만 알림

