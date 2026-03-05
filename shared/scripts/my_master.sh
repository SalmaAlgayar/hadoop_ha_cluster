#!/bin/bash

export HADOOP_HOME=/opt/hadoop
export PATH=$HADOOP_HOME/bin:$HADOOP_HOME/sbin:$PATH

service ssh start

DIR="/opt/hadoop/data/namenode"
num=$(hostname | grep -o '[0-9]*$')

if [ "$num" = "1" ]; then

  echo 2 > /opt/hadoop/data/zookeeper/myid

  /usr/share/zookeeper/bin/zkServer.sh start /opt/hadoop/data/zookeeper/zoo.cfg

  hdfs --daemon start journalnode

  sleep 15

  if [ -d "$DIR" ] && [ -z "$(ls -A "$DIR")" ]; then
    hdfs namenode -format -force
    hdfs namenode -initializeSharedEdits -force
    hdfs zkfc -formatZK -force
  fi

  hdfs --daemon start zkfc
  hdfs --daemon start namenode
  yarn --daemon start resourcemanager

else

  echo 3 > /opt/hadoop/data/zookeeper/myid

  /usr/share/zookeeper/bin/zkServer.sh start /opt/hadoop/data/zookeeper/zoo.cfg
  hdfs --daemon start journalnode

  until bash -c '</dev/tcp/my_master1/8020' 2>/dev/null; do
    sleep 2
  done

  if [ -d "$DIR" ] && [ -z "$(ls -A "$DIR")" ]; then
    hdfs namenode -bootstrapStandby -force
  fi

  hdfs --daemon start zkfc
  hdfs --daemon start namenode
  yarn --daemon start resourcemanager

fi