project page: https://launchpad.net/debug-logs-collector
ppa: https://launchpad.net/~alextu/+archive/ubuntu/pc-tools

usage:
  1. execute  collect-logs.sh
  2. the logs will be put in $HOME/collect-logs
  3. each time executing collect-logs.sh will add one more git commit in $HOME/collect-logs
  4. it's convenient to compare each commit difference by git-diff
  5. a cron service will be executed every 15 mins to check if lspci or lsusb changed.
