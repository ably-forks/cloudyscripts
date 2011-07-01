#!/bin/bash

BENCHMARK_FILE=$1
ZIP_FILE=$2
MISC_FILES="script_header.template header.template footer.template"
REPOSIT="checks"

if [ "${BENCHMARK_FILE}" = "" ] || [ "${ZIP_FILE}" = "" ]
then
	echo "USAGE: "$0" <benchmark group file> <target zip file>"
	exit 1
fi

#check that identifiers are unique
DUPLICATE_IDENTIFIERS=$( cd $REPOSIT && ls -1 *.check *.group | sed -e 's/\.[^.]*$//' | sort | uniq -d )

if [ ! "${DUPLICATE_IDENTIFIERS}" = "" ]
then
	for f in $( echo ${DUPLICATE_IDENTIFIERS} )
	do
		echo "WARNING: There exist several files with the same identifier: $f"
	done
fi

#check for identifiers that do not correspond to file names
WRONG_IDENTIFIERS=""

cd $REPOSIT
for f in *.check *.group
do
	FILENAME_ID=$( echo $f | sed -e 's/.[^.]*$//' )
	INTERNAL_ID=$( grep "ID:" $f | sed -e 's/^ID:\s*//' )

	if [ ! "${FILENAME_ID}" = "${INTERNAL_ID}" ]
	then 
		echo "WARNING: ID in file $f is different from file name"
	fi
done

#if zip file exists already, delete it
rm -f ../${ZIP_FILE}

#build list of tests required by benchmark
CHECKS_FIFO="${BENCHMARK_FILE%.group}"
DONE_CHECKS=""

while [ ! "${CHECKS_FIFO}" = "" ]
do
	CURRENT_CHECK=$( echo ${CHECKS_FIFO} | cut -d" " -f1 )
	CHECKS_FIFO=$( echo ${CHECKS_FIFO} | sed -e "s/${CURRENT_CHECK}//" )
	DONE_CHECKS="${DONE_CHECKS} ${CURRENT_CHECK}"

	echo "adding check: ${CURRENT_CHECK}"

	if [ -f "${CURRENT_CHECK}.group" ]
	then
		CHILDREN=$( ruby -r "yaml" -e "File.open('${CURRENT_CHECK}.group') {|f| x = YAML::load(f)['Children']; print x ? x.join(' ') : '' }" )
		#add child if it is not already in benchmark
		for f in $( echo ${CHILDREN} )
		do
			if ( ! echo ${CHECKS_FIFO} | grep $f 2>/dev/null 1>/dev/null ) && ( ! echo ${DONE_CHECKS} | grep $f 2>/dev/null 1>/dev/null )
			then
				CHECKS_FIFO="${CHECKS_FIFO} $f"
			fi
		done

		zip -9 ../${ZIP_FILE} "${CURRENT_CHECK}.group" 2>/dev/null 1>/dev/null
	elif [ -f "${CURRENT_CHECK}.check" ]
	then
		# get list of dependencies
		DEPENDENCIES=$( ruby -r "yaml" -e "File.open('${CURRENT_CHECK}.check') {|f| x = YAML::load(f)['Depends']; print x ? x.join(' ') : '' }" )

		for f in $( echo ${DEPENDENCIES} )
		do
			if ( ! echo ${CHECKS_FIFO} | grep $f 2>/dev/null 1>/dev/null ) && ( ! echo ${DONE_CHECKS} | grep $f 2>/dev/null 1>/dev/null )
			then
				CHECKS_FIFO="${CHECKS_FIFO} $f"
			fi
		done

		zip -9 ../${ZIP_FILE} "${CURRENT_CHECK}.check" 2>/dev/null 1>/dev/null
	else
		echo "WARNING: Unsatisfied dependency: ${CURRENT_CHECK}"
	fi
done

for f in $( echo ${MISC_FILES} )
do
	echo "adding file: $f"
	zip -9 ../${ZIP_FILE} $f 2>/dev/null 1>/dev/null
done

cd -
