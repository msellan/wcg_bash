#!/bin/bash

#+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
#+ World Community Grid Data Processing Script
#+
#+ This script uses the WCG API to download work units
#+ for a given member and reformats the data from JSON
#+ to CSV to load into a MySQL database.
#+
#+ By Mark Sellan
#+
#+ March 30, 2019
#+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

#---------> Define global variables <----------------------------------
#
#  Setting constants and "global" variables. Stored World Community
#  Grid "membername" and "verficationcode" in a separate script called
#  wcg_env which is sourced here.
#
#----------------------------------------------------------------------

source ~/wcg_env.sh

PATH="${PATH}":~/Downloads:/usr/bin:/Applications/MAMP/Library/bin
output_format=json
data_dir=~/Downloads
wcgdata_file="${data_dir}/wcgdata.dat"
dbname=wcg
output_file="${data_dir}/csv_out.dat"
api_url="https://www.worldcommunitygrid.org/api/members/${member_name}/results?code=${verification_code}&format=${output_format}"

#----------> Get a count of results <---------------------------------
#
#  This fucntion is a single call to the WCG API that retrieves the
#  number of workunits to download.  It is not currently in use but
#  left for future ideas.
#
#---------------------------------------------------------------------  

get_results_count () {

	results_count=$(curl -s "${api_url}" | grep -i Available | sed 's/,//' | awk -F : '{print $2}' | tr -d '"')
	echo "${results_count}"
}

#----------> Retrieve all work units in one pass <--------------------
#
#   This uses 'curl' to retrieve all available work units by using an
#   undocumented feature of the WCG API by setting the limit to zero.
#   The API documentation specifies using 'limit' and 'offset'. I have
#   a version that works with limit and offset as well but it is not
#   provided here. If you ask in a comment, I'll upload it.
#
#---------------------------------------------------------------------

retrieve_full_data () {
	
	return_limit=0
	curl -s "${api_url}"'&Limit='"${return_limit}" >> "${wcgdata_file}"
}


#----------> Parse keys/values <--------------------------------------
#
#  This function uses string manipulation in the shell (not a bashism;
#  this should work in any shell) to parse key/value pairs assigning 
#  only the values to a variable called 'value'. The construct is
#  ${var#*SubStr} where the beginning of the string up to the substring 
#  will be dropped. 
#
#  In the specific case from the code value="${line#*:}" 
#  the variable $line contains the key/value pair from the JSON separated
#  by ':' The key (the substring) up to and including the delimiter (':')
#  are dropped leaving the value to be assigned to the variable $value.
#
#---------------------------------------------------------------------

parse () {

value="${line#*:}" 
}

#----------> Create CSV SQL Load Script <-------------------------------
#
#  The main purpose of this function is to rewrite the JSON data from the
#  API into CSV format. create_load does most of the heavy lifting by reading
#  all output lines from the API after calling other functions to remove
#  JSON formatting and adding sql commands to create a sql load script.
#  There are 19 fields per record.
#
#  This function syncronizes the order of the fields adding a placeholder
#  with the Unix Epoch date for the one column that gets added dynamically
#  based on workunit status, "Receivedtime". But mostly it coverts newlines
#  to commas and inserts parentheses and newlines around each record. By
#  omitting the function calls to "create_insert" and "create_update" you
#  can simply derive a plain csv file.
#
#-----------------------------------------------------------------------

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

#----------> DeJSONify data <--------------------------------------------
#
#  This function uses an 'ex' editor script with a heredoc to strip out
#  JSON formatting provided by the API such as curly braces and extraneous
#  commas.
#
#------------------------------------------------------------------------

de_json () {

	ex "${wcgdata_file}" <<EOF
	1,6d
	g/{/s///g
	g/}/s///g
	g/^,/s//g
	wq!
EOF
}

#----------> Print ENV <--------------------------------------------------
#
#  print_env is not used by the script but provides troubleshooting 
#  information to see variables that are sourced from the wcg_env.sh script.
#
#-------------------------------------------------------------------------

print_env () {

source ~/wcg_env.sh
echo "${PATH}"
echo "${dbuser}"
echo "${dbpass}"
echo "${verification_code}"
echo "${member_name}"
}

#----------> Create MySQL table <-----------------------------------------
#
#  The create_table function is not used directly by the script but exists
#  to document the method used to create the 'wcg_workunits' table in the 
#  'wcg' MySQL database. It presumes an existing MySQL instance and database.
#
#-------------------------------------------------------------------------

create_table () {

mysql --login-path=local "${dbname}" -e 'CREATE TABLE `wcg_work_units_test` (`AppName` char(30) DEFAULT NULL,`ClaimedCredit` float DEFAULT NULL,`CpuTime` float DEFAULT NULL,`ElapsedTime` float DEFAULT NULL,`ExitStatus` int(11) DEFAULT NULL,`GrantedCredit` float DEFAULT NULL,`DeviceId` int(25) DEFAULT NULL,`DeviceName` char(30) DEFAULT NULL,`ModTime` int(30) DEFAULT NULL,`WorkunitId` int(30) NOT NULL,`ResultId` int(30) DEFAULT NULL,`Name` char(255) DEFAULT NULL,`Outcome` int(11) DEFAULT NULL,`ReceivedTime` datetime DEFAULT NULL,`ReportDeadline` datetime DEFAULT NULL,`SentTime` datetime DEFAULT NULL,`ServerState` int(11) DEFAULT NULL,`ValidateState` int(11) DEFAULT NULL,`FileDeleteState` int(11) DEFAULT NULL, PRIMARY KEY (`WorkunitId`)) ENGINE=InnoDB DEFAULT CHARSET=utf8;'
}

#----------> Create Insert <-----------------------------------------------
#
#  The create_insert function is called by the create_load function to 
#  build the beginning of the SQL load script. This provides the INSERT 
#  statement to insert new WCG workunit records into the database.
#
#--------------------------------------------------------------------------

create_insert () {

printf 'INSERT INTO `wcg_work_units` (`AppName`, `ClaimedCredit`, `CpuTime`, `ElapsedTime`, `ExitStatus`, `GrantedCredit`, `DeviceId`, `DeviceName`, `ModTime`, `WorkunitId`, `ResultId`, `Name`, `Outcome`, `ReceivedTime`, `ReportDeadline`, `SentTime`, `ServerState`, `ValidateState`, `FileDeleteState`)\nVALUES\n' >> "${output_file}"
}

#----------> Crete Update <-----------------------------------------------
#
#  The create_update function is called by the create_load function at the
#  end of the data values load to build the UPDATE statement to update
#  existing records in the database. This is not a stand-alone statement
#  but uses ON DUPLICATE KEY UPDATE as a part of the INSERT statement. The
#  WCG "WorkunitID" is the primary key for the database.
#
#--------------------------------------------------------------------------

create_update () {

printf 'ON DUPLICATE KEY UPDATE ClaimedCredit=values(ClaimedCredit),CpuTime=values(CpuTime),ElapsedTime=values(ElapsedTime),ExitStatus=values(ExitStatus),GrantedCredit=values(GrantedCredit),ModTime=values(ModTime),Outcome=values(Outcome),ReceivedTime=values(ReceivedTime),ServerState=values(ServerState),ValidateState=values(ValidateState),FileDeleteState=values(FileDeleteState);\n' >> "${output_file}"
}

#----------> Tidy <---------------------------------------------------------
#
#  The tidy function performs two tasks: 
#      1. It swaps the order of ,) to ), to correctly separate each SQL
#         command.
#      2. It removes the last line of the output file which contains an
#         extraneous ')' in the "values" created by the create_load function.
#
#---------------------------------------------------------------------------

tidy () {
	
	ex "${output_file}" <<EOF
	g/,)/s/,)/),/g
	$
	-1,.d
	wq!
EOF
}

#----------> Reset and archive <------------------------------------------
#
#  The archive_results function moves the datafile returned by the WCG API
#  and the ouput file generated by the create_load function to date/timestamped
#  filenames and thus clears the original names for the next run.
#
#-------------------------------------------------------------------------

archive_results () {

	if [[ -s "${output_file}" ]]; then
		date_stamp=$(date +%Y-%m-%d.%H:%M:%S)
		mv "${output_file}" "${output_file}"."${date_stamp}"
		mv "${wcgdata_file}" "${wcgdata_file}"."${date_stamp}"
	fi
}

#----------> Load Data <--------------------------------------------------
#
#  The load_data function simply executes the SQL load script built by the
#  create_load function. It is not called directly in Main but called by
#  the test_mysql function.
#
#-------------------------------------------------------------------------

load_data () {

	mysql --login-path=local "${dbname}" < "${output_file}"
}

#----------> Test SQL Connection <---------------------------------------
#
#  Tests the connection to MySQL by logging in to a specific database. It
#  echos exit to ensure the test exits.  If successful it calls the 
#  load_data function otherwise it logs the error to syslog and exits.
#
#------------------------------------------------------------------------

test_mysql () {

	echo "exit" | mysql --login-path=local "${dbname}" 

	if [[ $? -eq 0 ]]; then

		load_data
	else
		logger -s -t WCG "MySQL appears to be down"
		exit
	fi
}

#----------> Main functions <-------------------------------------------
#
#  Grouping of directly called functions used in the Main Execution
#  body of the script.
#
#-----------------------------------------------------------------------

main () {

#print_env
#create_table
#get_results_count

retrieve_full_data
create_load
test_mysql
archive_results
}

#----------> Main Execution <------------------------------------------
#
#  Script execution starts here
#
#----------------------------------------------------------------------

main
