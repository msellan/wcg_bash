#!/bin/bash

#+++++++++++++++++++++++++++++++++++++++++++++++++++++
#+ World Community Grid Data Processing Script
#+
#+ This script uses the WCG API to download work units
#+ for a given member and reformats the data from JSON
#+ to CSV to load into a MySQL database.
#+
#+ By Mark Sellan
#+
#+ March 30, 2019
#+++++++++++++++++++++++++++++++++++++++++++++++++++++

#==========> Define global variables <============

source ~/wcg_env.sh

PATH="${PATH}":~/Downloads:/usr/bin:/Applications/MAMP/Library/bin
output_format=json
data_dir=~/Downloads
wcgdata_file="${data_dir}/wcgdata.dat"
dbname=wcg
output_file="${data_dir}/csv_out.dat"
api_url="https://www.worldcommunitygrid.org/api/members/${member_name}/results?code=${verification_code}&format=${output_format}"

#===========>  Get a count of results <============

get_results_count () {

	results_count=$(curl -s "${api_url}" | grep -i Available | sed 's/,//' | awk -F : '{print $2}' | tr -d '"')
	echo "${results_count}"
}

#===========> Retrieve all work units in one pass <============

retrieve_full_data () {
	
	return_limit=0
	curl -s "${api_url}"'&Limit='"${return_limit}" >> "${wcgdata_file}"
}

#===========> Parse key/values  <==============

parse () {

value="${line#*:}" 
}

#==========> Create CSV SQL Load Script<============

create_load () {

de_json
create_insert

i=0
while read -r line
do
	if echo "${line}" | grep -qi app; then
	
		i=1
		printf '(' >> "${output_file}"
	fi
	
	if echo "${line}" | grep -qi report && [ $i == 14 ]; then
		
		parse
                printf "\"1970-01-01T00:00:00\"," >> "${output_file}"
                printf "${value}" >> "${output_file}"
        
	elif [ "${line}" == '' ]; then
	
		printf ')' >> "${output_file}"
                printf '\n' >> "${output_file}"
        else
		parse
                printf "${value}" >> "${output_file}"
        fi

        ((i++))

	if [ ${i} == 19 ]; then
		i=0
	fi

done < "${wcgdata_file}"

tidy
create_update
}

#==========> DeJSONify data <===========

de_json () {

	ex "${wcgdata_file}" <<EOF
	1,6d
	g/{/s///g
	g/}/s///g
	g/^,/s//g
	wq!
EOF
}

#========> Print ENV <===========

print_env () {

source ~/wcg_env.sh
echo "${PATH}"
echo "${dbuser}"
echo "${dbpass}"
echo "${verification_code}"
echo "${member_name}"
}

#==========> Create table <===========

create_table () {

mysql --login-path=local "${dbname}" -e 'CREATE TABLE `wcg_work_units_test` (`AppName` char(30) DEFAULT NULL,`ClaimedCredit` float DEFAULT NULL,`CpuTime` float DEFAULT NULL,`ElapsedTime` float DEFAULT NULL,`ExitStatus` int(11) DEFAULT NULL,`GrantedCredit` float DEFAULT NULL,`DeviceId` int(25) DEFAULT NULL,`DeviceName` char(30) DEFAULT NULL,`ModTime` int(30) DEFAULT NULL,`WorkunitId` int(30) NOT NULL,`ResultId` int(30) DEFAULT NULL,`Name` char(255) DEFAULT NULL,`Outcome` int(11) DEFAULT NULL,`ReceivedTime` datetime DEFAULT NULL,`ReportDeadline` datetime DEFAULT NULL,`SentTime` datetime DEFAULT NULL,`ServerState` int(11) DEFAULT NULL,`ValidateState` int(11) DEFAULT NULL,`FileDeleteState` int(11) DEFAULT NULL, PRIMARY KEY (`WorkunitId`)) ENGINE=InnoDB DEFAULT CHARSET=utf8;'
}

#========> Create Insert <========

create_insert () {

printf 'INSERT INTO `wcg_work_units` (`AppName`, `ClaimedCredit`, `CpuTime`, `ElapsedTime`, `ExitStatus`, `GrantedCredit`, `DeviceId`, `DeviceName`, `ModTime`, `WorkunitId`, `ResultId`, `Name`, `Outcome`, `ReceivedTime`, `ReportDeadline`, `SentTime`, `ServerState`, `ValidateState`, `FileDeleteState`)\nVALUES\n' >> "${output_file}"
}

#========> Create Update <=========

create_update () {

printf 'ON DUPLICATE KEY UPDATE ClaimedCredit=values(ClaimedCredit),CpuTime=values(CpuTime),ElapsedTime=values(ElapsedTime),ExitStatus=values(ExitStatus),GrantedCredit=values(GrantedCredit),ModTime=values(ModTime),Outcome=values(Outcome),ReceivedTime=values(ReceivedTime),ServerState=values(ServerState),ValidateState=values(ValidateState),FileDeleteState=values(FileDeleteState);\n' >> "${output_file}"
}

#======> Tidy <============

tidy () {
	
	ex "${output_file}" <<EOF
	g/,)/s/,)/),/g
	$
	-1,.d
	wq!
EOF
}

#=======> Reset and archive <=========

archive_results () {

	if [[ -s "${output_file}" ]]; then
		date_stamp=$(date +%Y-%m-%d.%H:%M:%S)
		mv "${output_file}" "${output_file}"."${date_stamp}"
		mv "${wcgdata_file}" "${wcgdata_file}"."${date_stamp}"
	fi
}

#===========> Load Data <===========

load_data () {

	mysql --login-path=local "${dbname}" < "${output_file}"
}

#=========> Main Function <============

main () {

#print_env
#create_table
#get_results_count

retrieve_full_data
create_load
load_data
archive_results
}

#==========> Main Execution <============

main
