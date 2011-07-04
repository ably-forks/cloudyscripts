#!/bin/sh

if [ "${1##--}" = "version" ]
then
	echo "internal helper"
	exit 0
fi


NB_LINES=${1##-}

#test if number of lines parameter is really numerical
NB_LINES_FILTERED=${NB_LINES##[0-9]}
NB_LINES_FILTERED=${NB_LINES_FILTERED##[0-9]}
NB_LINES_FILTERED=${NB_LINES_FILTERED##[0-9]}
if [ -z "${NB_LINES_FILTERED}" ]
then 
	shift
else
	NB_LINES=10
fi

#if 0 lines of head, simply return
if [ "${NB_LINES}" -le 0 ]
then
	return 0
fi

# test if second parameter is given
if [ -z "$1" ]
then
	INPUT_FILE=/dev/stdin
else
	TEMPFILE=/tmp/$$
	mkfifo ${TEMPFILE}
	cat "$1" > ${TEMPFILE} &
	INPUT_FILE=${TEMPFILE}
fi

#read each line and count down the line counter
while read LINE < ${INPUT_FILE}
do
	echo ${LINE}
	NB_LINES=$((${NB_LINES}-1))
	#if line counter reaches zero, it's finished
	if [ "${NB_LINES}" -le 0 ]
	then
		if [ ! -z "${TEMPFILE}" ]
		then
			rm ${TEMPFILE}
		fi
		return 0
	fi
done

if [ ! -z "${TEMPFILE}" ]
then
	rm ${TEMPFILE}
fi
