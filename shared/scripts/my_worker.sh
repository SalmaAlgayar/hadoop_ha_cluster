#!/bin/bash

export HADOOP_HOME=/opt/hadoop
export PATH=$HADOOP_HOME/bin:$HADOOP_HOME/sbin:$PATH

service ssh start

until bash -c '</dev/tcp/my_master1/8020' 2>/dev/null; do
  sleep 2
done

hdfs --daemon start datanode
yarn --daemon start nodemanager