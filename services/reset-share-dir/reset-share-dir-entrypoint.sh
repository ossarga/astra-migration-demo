#!/bin/bash

rm -f /run/share/*
touch /run/share/.keepdir
touch /run/share/.hosts_lock.free
touch /run/share/.zdm_restart_lock.free

ls -alh /run/share