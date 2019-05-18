<img style="float: left; margin: 0px 15px 15px 0px;" src="https://pbs.twimg.com/profile_images/448919987281866752/T4oA5jtc_400x400.png" width="100" />
<h1>WCG_bash</h1> 

WCG_bash is a bash script that uses the World Community Grid API to download workunit data and reprocess that data from JSON to CSV and then load the data into a MySQL database. This script presumes the existence of a running instance of MySQL but provides a function to correctly create the table to accomodate the WCG schema. 

<b>Important:</b> It also requires that you set up your MySQL client with the MySQL Config Editor to allow encrypted passwordless access.  Lastly, you will need to create a script called wcg_env.sh with your WCG "member name" and WCG "Verfication Code" which can both be found on your WCG profile page.


<h2>Installation and Use</h2>

Copy the script, <code>wcg_api_new.sh</code> into your home directory or subdirectory of choice and then create a file called <code>wcg_env.sh</code> and place that somewhere such as your home directory and set permisisons so that it's readable only by 'owner' - chmod 600 since it contains your WCG APIkey. In that file you'll need to add lines to export variables that are sourced by the main script at runtime. A sample looks like this:
		
			#!/bin/bash
		       
			export dbuser="dbuser"
			export dbpass="password"
			export verification_code="18ad6defdadee4b3a1e33d91a67cy25c"
			export member_name="wcg_member" 

Strickly speaking the first two lines of the script that contain the database userID and password are not needed or used.  I keep them there for troublshooting purposes only. Database credentials are described in the next paragraph.  But you do need the last two lines.  They contain the WCG 'verification_code' and your WCG 'member_name' which you can find on your WCG 'Profile' page and are what enable you to use the WCG API.

Next, you need to have access to a MySQL database. The script has a function that shows how the database table 'wcg_work_units' was created for my instance and that works with this script.  Create the table in your database.  It only has to be done once. I would suggest creating a user with limited privileges to assign to this table.  My user has 'select', 'insert', and 'update' privileges and that's it. To use the MySQL credentials in the script, you need to use the MySQL Config Editor to create an encrypted, passwordless connection.  Be sure too, to update the PATH variable in the script to include any directories you've used to install the scripts or MySQL if they are outside your current path.

Make sure the script itself is executable with a <code> chmod 755 wcg_api_new.sh</code> or 750 or 700 based on your preferences.  Execute the script by running it on the command line or by calling in through 'cron' if you want to run it on a schedule.

You can also use the script to simply generate a CSV file and not load the contents to a database. Specify "-c" at runtime to merely create a CSV file as the output.  If you want to load data into your MySQL database then specify "-l" (for load) as an option.


<h2>Function descriptions</h2>

<h3>get_results_count</h3>

This is a single call to the API that retrieves the number of workunits to download. It is not used directly by the script but can be called at runtime with the "-g" option at runtime.

<h3>retrieve_full_data</h3>

This uses 'curl' to retrieve all available work units by using an undocumented feature of the WCG API by setting the limit to zero.  The API documentation specifies using 'limit' and 'offset'. I have a version that works with limit and offset as well but it is not provided here. If you ask in a comment, I'll upload it.

<h3>parse</h3>

This function uses string manipulation in the shell (not a bashism - this should work in any shell) to parse key/value pairs assigning only the values to a variable called 'value'. The construct is <code>${var#*SubStr}</code> where the beginning of the string up to the substring will be dropped.  In the specific case from the code <code>value="${line#\*:}"</code> the variable $line contains the key/value pair from the JSON separated by ':'  The key (the substring) up to and including the delimiter (':') are dropped leaving the value to be assigned to the variable $value.

<h3>create_load</h3>

The <code>create_load</code> does most of the heavy lifting by reading all output lines from the API after calling other functions to remove JSON formatting and adding sql commands to create a sql load script. There are 19 fields per record.  

This function synchronizes the order of the fields adding a placeholder for the one column that gets added dynamically based on workunit status, "Receivedtime".  But mostly it coverts newlines to commas and inserts parentheses and newlines around each record. 

NOTE:  You an derive a plain CSV file instead of a SQL load script by setting "-c" as an argument at runtime in place of "-l" which loads the data to MySQL.

<h3>de_json</h3>

<code>de_json</code> uses an 'ex' editor script/heredoc to strip out JSON formatting such as curly braces and extraneous commas.

<h3>tidy</h3>

The <code>tidy</code> function performs two tasks - 1) it swaps the order of ,) to ), to correctly separate each SQL command and removes the last line of the output file which contains an extraneous ')' in the "values" created by the create_load function.

<h3>create_table</h3>

The <code>create_table</code> function is not used directly by the script but can be called in interactive mode aand used to create the 'wcg_workunits' table in the 'wcg' MySQL database. It presumes an existing MySQL instance and database. Specify option "-t" at runtime.

<h3>print_env</h3>

<code>print_env</code> is not used by the script but provides a troubleshooting tool to see varibles that are sourced from the wcg_env.sh script. It can be called at runtime with "-e" option.

<h3>load_data</h3>

The <code>load_data</code> function simply executes the SQL load script built by the <code>create_load</code> function. Use the "-l" opton to select at runtime/

<h3>archive_results</h3>

The <code>archive_results</code> function moves the datafile returned by the WCG API and the ouput file generated by the <code>create_load</code> function to date/timestamped filenames and thus clears the original names for the next run.






