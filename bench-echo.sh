#!/bin/bash

program_name=$0

function print_usage {
    echo ""
    echo "Usage: $program_name [connections] [duration] [size]"
    echo ""
    echo "connections:  Connections to keep open to the destinations"
    echo "duration:     Exit after the specified amount of time"
    echo "size:         single packet size for benchmark"
    echo ""
    echo "--- EXAMPLE ---"
    echo ""
    echo "$program_name 1000 30 1024"
    echo ""
    exit 1
}

# if less than two arguments supplied, display usage
if [  $# -le 1 ]; then
  print_usage
  exit 1
fi

# check whether user had supplied -h or --help . If yes display usage
if [[ ( $# == "--help") ||  $# == "-h" ]]; then
  print_usage
  exit 0
fi

set -e

echo ""
echo "--- BENCH ECHO START ---"
echo ""

cd "$(dirname "${BASH_SOURCE[0]}")"
function cleanup() {
  echo "--- BENCH ECHO DONE ---"
  # shellcheck disable=SC2046
  kill -9 $(jobs -rp)
  # shellcheck disable=SC2046
  wait $(jobs -rp) 2>/dev/null
}
trap cleanup EXIT

mkdir -p bin

eval "$(pkill -9 -f echo-net || printf "")"
eval "$(pkill -9 -f echo-evio || printf "")"
eval "$(pkill -9 -f echo-netpoll || printf "")"
eval "$(pkill -9 -f echo-gnet || printf "")"

conn_num=$1
test_duration=$2
packet_size=$3
#packet=$(< /dev/urandom tr -dc 'a-zA-Z0-9' | fold -w "$packet_size" | head -n 1)
packet=$(LC_ALL=C bash -c "< /dev/urandom tr -dc a-zA-Z0-9 | fold -w $packet_size | head -n 1")

echo "--- ECHO PACKET ---"
echo "$packet"
echo ""

function go_bench() {
  echo "--- $1 ---"
  echo ""
  if [[ "$1" == "GNET" ]]; then
    go build -tags=poll_opt -gcflags="-l=4" -ldflags="-s -w" -o "$2" "$3"
  else
    go build -gcflags="-l=4" -ldflags="-s -w" -o "$2" "$3"
  fi

  if [[ "$1" == "GO-NET" || "$1" == "NETPOLL" ]]; then
    $2 --port "$4" &
  elif [[ "$1" == "GNET" ]]; then
    $2 --port "$4" --multicore="$5" &
  else
    $2 --port "$4" --loops "$5" &
  fi

  echo "Warming up for 1 seconds..."
  sleep 1
  echo ""

  echo "--- BENCHMARK START ---"
  printf "*** %d connections, %d seconds, packet size: %d bytes\n" "$conn_num" "$test_duration" "$packet_size"
  echo ""
  
  tcpkali --connections "$conn_num" --connect-rate "$conn_num" --duration "$test_duration"'s' -m "$packet" 127.0.0.1:"$4"
  echo ""
  echo "--- BENCHMARK DONE ---"
  echo ""
}

go_bench "GO-NET" bin/echo-net-server echo-net-server/main.go 7000
go_bench "EVIO" bin/echo-evio-server echo-evio-server/main.go 7001 -1
go_bench "GNET" bin/echo-gnet-server echo-gnet-server/main.go 7002 true
go_bench "NETPOLL" bin/echo-netpoll-server echo-netpoll-server/main.go 7003
