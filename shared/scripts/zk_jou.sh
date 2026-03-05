#!/bin/bash

export HADOOP_HOME=/opt/hadoop
export PATH=$HADOOP_HOME/bin:$HADOOP_HOME/sbin:$PATH

service ssh start

echo 1 > /opt/hadoop/data/zookeeper/myid

/usr/share/zookeeper/bin/zkServer.sh start /opt/hadoop/data/zookeeper/zoo.cfg

hdfs --daemon start journalnode