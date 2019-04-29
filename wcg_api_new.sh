#!/bin/bash

#+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
#+ World Community Grid Data Processing Script
#+
#+ This script uses the WCG API to download work units for a given member and
#+ reformats the data from JSON to CSV to load into a MySQL database.
#+
#+ By Mark Sellan
#+
#+ Created March 30, 2019
#+
#+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
#+
#+ License
#+
#+ Copyright (C) 2019 Mark Sellan
#+
#+  This program is free software: you can redistribute it and/or modify it 
#+  under the terms of the GNU General Public License as published by the Free
#+  Software Foundation, either version 3 of the License, or (at your option)
#+  any later version.
#+
#+  This program is distributed in the hope that it will be useful, but WITHOUT
#+  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
#+  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License 
#+  for more details.
#+
#+  You should have received a copy of the GNU General Public License along 
#+  with this program.  If not, see <https://www.gnu.org/licenses/>.
#+
#+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
#
#  Change History
#
#  04-16-19 - Added MySQL error checking function and incorporated README text
#	      from GitHub into the script body
#  04-20-19 - Added license details to script body
#  04-24-19 - Corrected two rookie-like mistakes and rewrote create_load
#	      function to use =~ bashism to replace the use of grep to
#	      speed-up processing. 
#  04-26-19   Added parameterization with a case statement to allow individial
#  	      functions to be called at run time either in an interactive mode
#      	      or in a batch mode.
#  04-27-19   Rewrote create_load to consolidate create_insert and create_update
#  	      functions and made tweaks to the 'tidy' function.
#
#+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++


#---------> Define global variables <-------------------------------------------
#
#  Setting constants and "global" variables. Stored World Community Grid
#  "membername" and "verficationcode" in a separate script called wcg_env which
#  is sourced here.
#
#-------------------------------------------------------------------------------

source ~/wcg_env.sh

PATH="${PATH}":~/Downloads:/usr/bin:/Applications/MAMP/Library/bin
output_format=json
data_dir=~/Downloads
wcgdata_file="${data_dir}/wcgdata.dat"
dbname=wcg
output_file="${data_dir}/csv_out.dat"
api_url="https://www.worldcommunitygrid.org/api/members/${member_name}/results?code=${verification_code}&format=${output_format}"

#----------> Get a count of results <-------------------------------------------
#
#  Call to the WCG API to retrieve and calculates the number of workunits to
#  download.  It's not used except in interactive mode to display the count. 
#
#------------------------------------------------------------------------------- 

get_results_count () {

    if [[ "${interactive}" == true ]]; then
        results_count=$(curl -s "${api_url}" | grep -i Available \
        | sed 's/,//' | awk -F : '{print $2}' | tr -d '"')
        echo "${results_count}"
    else
        echo "Sorry this function is only available in interactive mode"
        exit -1
    fi
}

#----------> Retrieve all work units in one pass <------------------------------
#
#   This uses 'curl' to retrieve all available work units by using an 
#   undocumented feature of the WCG API by setting the limit to zero. The API 
#   documentation specifies using 'limit' and 'offset'. 
#
#-------------------------------------------------------------------------------

retrieve_full_data () {
	
    return_limit=0
    curl -s "${api_url}"'&Limit='"${return_limit}" >> "${wcgdata_file}"
}

#----------> Parse keys/values <------------------------------------------------
#
#  This function uses string manipulation in the shell (not a bashism; this
#  should work in any shell) to parse key/value pairs assigning only the values
#  to a variable called 'value'. The construct is ${var#*SubStr} where the
#  beginning of the string up to the substring will be dropped. 
#
#  In the specific case from the code value="${line#*:}" the variable $line
#  contains the key/value pair from the JSON separated  by ':' The key
#  (the substring) up to and including the delimiter (':') are dropped leaving
#  the value to be assigned to the variable $value.
#
#-------------------------------------------------------------------------------

parse () {

    value="${line#*:}" 
}

#----------> Create CSV SQL Load Script <---------------------------------------
#
#  This function syncronizes the order of the fields adding a placeholder field
#  with the Unix Epoch date to represent the WCG dynamically added column, 
#  "Receivedtime". But mostly it coverts newlines to commas and inserts
#  parentheses and newlines around each record. 
#
#-------------------------------------------------------------------------------

create_load () {

    printf 'INSERT INTO `wcg_work_units` 
        (`AppName`,
        `ClaimedCredit`,
        `CpuTime`,
        `ElapsedTime`,
        `ExitStatus`,
        `GrantedCredit`,
        `DeviceId`,
        `DeviceName`,
        `ModTime`, 
        `WorkunitId`,
        `ResultId`,
        `Name`,
        `Outcome`,
        `ReceivedTime`,
        `ReportDeadline`,
        `SentTime`,
        `ServerState`, 
        `ValidateState`, 
        `FileDeleteState`)\nVALUES\n' >> "${output_file}"

    i=0
    while read -r line
    do
        if [[ "${line}" =~ App ]]; then

            i=1
            printf '(' >> "${output_file}"
        fi
	
        if [[ "${line}" =~ Report ]] && [[ $i -eq 14 ]]; then
		
            parse
            printf "\"1970-01-01T00:00:00\"," >> "${output_file}"
            printf "${value}" >> "${output_file}"
    
        elif [[ "${line}" == '' ]]; then

            printf ')' >> "${output_file}"
            printf '\n' >> "${output_file}"
        else
            parse
            printf "${value}" >> "${output_file}"
        fi

        ((i++))
	
        if [[ ${i} -eq 19 ]]; then
            i=0
        fi

    done < "${wcgdata_file}"

    tidy

    printf 'ON DUPLICATE KEY UPDATE 
        ClaimedCredit=values(ClaimedCredit),
        CpuTime=values(CpuTime),
        ElapsedTime=values(ElapsedTime),
        ExitStatus=values(ExitStatus),
        GrantedCredit=values(GrantedCredit),
        ModTime=values(ModTime),
        Outcome=values(Outcome),
        ReceivedTime=values(ReceivedTime),
        ServerState=values(ServerState),
        ValidateState=values(ValidateState),
        FileDeleteState=values(FileDeleteState);\n' >> "${output_file}"
}

#----------> DeJSONify data <---------------------------------------------------
#
#  This function uses an 'ex' editor script with a heredoc to strip out JSON
#  formatting provided by the API such as curly braces and extraneous commas.
#
#-------------------------------------------------------------------------------

de_json () {

    ex "${wcgdata_file}" <<EOF
        1,6d
        g/{/s///g
        g/}/s///g
        g/^,/s//g
        g/]/s///g
        wq!
EOF
}

#----------> Print ENV <--------------------------------------------------------
#
#  print_env is not used by the script but provides troubleshooting 
#  information to see variables that are sourced from the wcg_env.sh script.
#
#-------------------------------------------------------------------------------

print_env () {

    source ~/wcg_env.sh
    echo "${PATH}"
    echo "${dbuser}"
    echo "${dbpass}"
    echo "${verification_code}"
    echo "${member_name}"
}

#----------> Create MySQL table <-----------------------------------------------
#
#  The create_table function is not used directly by the script but  called in
#  interactive mode to create the 'wcg_workunits' table in a 'wcg' MySQL 
#  database. It presumes an existing MySQL instance and database.
#
#-------------------------------------------------------------------------------

create_table () {

    if [[ "${interactive}" == true ]]; then

        mysql --login-path=local "${dbname}" -e 'CREATE TABLE `wcg_work_units_test2`
        (`AppName` char(30) DEFAULT NULL,
        `ClaimedCredit` float DEFAULT NULL,
        `CpuTime` float DEFAULT NULL,
        `ElapsedTime` float DEFAULT NULL,
        `ExitStatus` int(11) DEFAULT NULL,
        `GrantedCredit` float DEFAULT NULL,
        `DeviceId` int(25) DEFAULT NULL,
        `DeviceName` char(30) DEFAULT NULL,
        `ModTime` int(30) DEFAULT NULL,
        `WorkunitId` int(30) NOT NULL,
        `ResultId` int(30) DEFAULT NULL,
        `Name` char(255) DEFAULT NULL,
        `Outcome` int(11) DEFAULT NULL,
        `ReceivedTime` datetime DEFAULT NULL,
        `ReportDeadline` datetime DEFAULT NULL,
        `SentTime` datetime DEFAULT NULL,
        `ServerState` int(11) DEFAULT NULL,
        `ValidateState` int(11) DEFAULT NULL,
        `FileDeleteState` int(11) DEFAULT NULL,
         PRIMARY KEY (`WorkunitId`)) ENGINE=InnoDB DEFAULT CHARSET=utf8;'
    else
        echo "Sorry this function is only available in interactive mode"
        exit -1
    fi
}

#----------> Tidy <-------------------------------------------------------------
#
#  The tidy function performs two tasks: 
#      1. It swaps the order of ,) to ), to correctly separate each SQL
#         command.
#      2. It removes the last line of the output file which contains an
#         extraneous ')' in the "values" created by the create_load function.
#
#-------------------------------------------------------------------------------

tidy () {
	
    ex "${output_file}" <<EOF
        g/,)/s/,)/),/g
        $
        -2,.d
        wq!
EOF
}

#----------> Reset and archive <------------------------------------------------
#
#  The archive_results function moves the datafile returned by the WCG API and
#  the ouput file generated by the create_load function to date/timestamped
#  filenames and thus clears the original names for the next run.
#
#-------------------------------------------------------------------------------

archive_results () {

    if [[ -s "${output_file}" ]]; then
	date_stamp=$(date +%Y-%m-%d.%H:%M:%S)
	mv "${output_file}" "${output_file}"."${date_stamp}"
	mv "${wcgdata_file}" "${wcgdata_file}"."${date_stamp}"
    fi
}

#----------> Load Data <--------------------------------------------------------
#
#  The load_data function simply executes the SQL load script built by the
#  create_load function. 
#
#-------------------------------------------------------------------------------

load_data () {

    mysql --login-path=local "${dbname}" < "${output_file}"

}

#----------> Test SQL Connection <----------------------------------------------
#
#  Tests the connection to MySQL by logging in to a specific database. It echos
#  'exit' to ensure the test exits.  If successful it calls the load_data 
#  function otherwise it logs the error to syslog and exits.
#
#-------------------------------------------------------------------------------

test_mysql () {

    echo "exit" | mysql --login-path=local "${dbname}" 

    if [[ $? -eq 0 ]]; then

	load_data
    else
	logger -s -t WCG "MySQL appears to be down"
	exit
    fi

}

#----------> Show Usage <-------------------------------------------------------
#
#  Shows usage and can be called from the command line or will be displayed
#  anytime an incorrect number of arguments is passed on the command line
#
#-------------------------------------------------------------------------------

showUsage () {

  echo
  echo "usage: ${SCRIPT} [-i|-I] [-b|-B] <action> "
  echo
  echo "  where -i|-I = run interactively "
  echo "        -b|-B = process in batch mode"
  echo
  echo "       action = getcounts|createtable"
  echo
  echo "  (NOTE: PREVIEW and BATCH options are mutually exclusive!)"
  echo
}

#----------> Main execution <---------------------------------------------------
#
#  Processes commandline arguments testing for interactive mode or batch mode
#  operation and also executes the function or set of functions required for
#  the desired task.
#
#-------------------------------------------------------------------------------


#--------->  Make sure we have some arguments <---------------------------------

[[ $# -eq 0 ]] && showUsage && exit -1

matched=`expr "$1" : '-[iIbB]'`

if [[ $matched -gt 0 ]]; then
case $1 in
        -i|-I) interactive=true;;
        -b|-B) batch=true;;
esac
shift
fi

#----------> Make sure interactive and batch aren't both selected <-------------

[[ $# -eq 0 ]] && showUsage && exit -1

matched=`expr "$1" : '-[iIbB]'`

if [[ $matched -gt 0 ]]; then
echo "\nerror: can't have i and b\n"
exit -1
fi

#----------> Process main arguments <-------------------------------------------

[[ $# -eq 0 ]] && showUsage && exit -1

action=$1

case $action in

	getcounts) get_results_count
	   ;;
	showenv) print_env
	   ;;
	createtable) create_table
 	   ;;
	runmain)
	  retrieve_full_data
	  de_json
	  create_load
	  test_mysql
	  archive_results
	  ;;
	createcsv);;
	showusage) showUsage
	  ;;
	*)
	exit -1
	;;
esac

