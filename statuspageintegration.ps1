###StatusPageIntegration.ps1
#Author: Ryan Holland
#Email: ryan@ryanaholland.com
#GitHub: .....
#Last Updated: 6/4/2019
#Requirements:
#Need to have the following folder: C:\batch\statuspage  to store the xml file in

param (
        [string]$phase 
 )

##Activate alternative TSL/SSL
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
##ENTER YOUR DATA HERE
$apitoken = "{{api-key}}"
$pageid = "{{page-id}}"  #Can be taken from the admin portal URL
$componentid = "{{component-id}}"

##Define Header Data
$oauth = "OAuth $apitoken"
##Define Times (Local) Must be just in hour, so 3am would be '3'
$start = [DateTime]::Today.AddHours(3)
$end = [DateTime]::Today.AddHours(9)
$nowz = [DateTime]::Now

 switch ($phase) {
    "1" {
            ###This Phase of the script is to create the scheduled maintenance notifications
            Write-Host "This Phase of the script is to create the scheduled maintenance notifications"

            ##Get Dates

            #If script is ran after start time, create for the next day
            if ($start.TimeOfDay -le $nowz.TimeOfDay) {
                $startdate = [System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId( [DateTime]::Today.AddHours(3).AddDays(1), 'UTC')
                $enddate = [System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId( [DateTime]::Today.AddHours(9).AddDays(1), 'UTC')
              } Else {
                $startdate = [System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId( [DateTime]::Today.AddHours(3), 'UTC')
                $enddate = [System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId( [DateTime]::Today.AddHours(9), 'UTC')
              }

            $starttime =  $startdate.ToString("s")+"Z"
            $endtime =  $enddate.ToString("s")+"Z"

            ##Define API Data
            $params = @{"incident[name]"="PLM Full Backup";
            "incident[status]"="scheduled";
            "incident[scheduled_for]"=$starttime;
            "incident[scheduled_until]"=$endtime;
            "incident[auto_tweet_at_beginning]"="false";
            "incident[scheduled_remind_prior]"="false";
            "incident[scheduled_auto_completed]"="false";
            "incident[auto_transition_deliver_notifications_at_end]"="false";
            "incident[auto_transition_deliver_notifications_at_start]"="false";
            "incident[auto_transition_to_maintenance_state]"="false";
            "incident[auto_transition_to_operational_state]"="false";
            "incident[component_ids][]"="$componentid";
            "incident[components][$componentid]"="operational";
            "incident[deliver_notifications]"="false";
            "incident[body]"="PLM will be down for backup between 3:00am and 9:00am";
            }
            ##Invoke API to Create new Scheduled maintenance incident
            $curlurl = 'https://api.statuspage.io/v1/pages/' + $pageid + '/incidents'
            $rawoutput = Invoke-WebRequest -Headers @{"Authorization" = "$oauth"} -Method POST `
                            -Uri $curlurl `
                            -ContentType application/x-www-form-urlencoded `
                            -Body $params
            #Take output from pipeline and convert to JSON (only the content returned from the Invoke)
            $cleanoutput = ConvertFrom-Json $rawoutput.Content
            #Store in file for Phase2
            $cleanoutput | Export-CliXml c:\batch\statuspage\output.xml
            break
    }
    "2" {
           ##Phase 2 is invoked when the services have stopped, this makes the maintenance job enter the "In Progress" Phase and sets PLM to "maintenance"
           Write-Host "Phase 2 is invoked when the services have stopped, this makes the maintenance job enter the 'In Progress' Phase and sets PLM to 'maintenance'"
           ##Read out data from Phase 1
            $cleanoutput = Import-CliXml c:\batch\statuspage\output.xml

            ##Define new URL with output
            $curlpost = 'https://api.statuspage.io/v1/pages/' + $pageid + '/incidents/' + $cleanoutput.id +'.json'

            ##Define API Data
            $params = @{"incident[name]"="PLM Backup";
            "incident[status]"="in_progress"; #Change to in progress
            "incident[component_ids][]"="$componentid";
            "incident[components][$componentid]"="under_maintenance";
            "incident[deliver_notifications]"="false";
            "incident[body]"="PLM is now down for maintenance, check about around 9:00am CST for an updated status.";
            }

            ##Invoke API to Update/Activate Incident
            $rawoutput = Invoke-WebRequest -Headers @{"Authorization" = "$oauth"} -Method PATCH `
                            -Uri $curlpost `
                            -ContentType application/x-www-form-urlencoded `
                            -Body $params
            #Take output from pipeline and convert to JSON (only the content returned from the Invoke)
            $cleanoutput = ConvertFrom-Json $rawoutput.Content
            #Store in file for Phase 3
            $cleanoutput | Export-CliXml c:\batch\statuspage\output.xml
           break
    }
    "3" {
            ##Phase 3 is invoked when the services are back up, this makes the maintenance job enter the "Verifying" Phase and returns PLM to "operational"
            Write-Host "Phase 3 is invoked when the services are back up, this makes the maintenance job enter the 'Verifying' Phase and returns PLM to 'operational'"
            ##Read out data from Phase 2
            $cleanoutput = Import-CliXml c:\batch\statuspage\output.xml

            ##Define new URL with output
            $curlpost = 'https://api.statuspage.io/v1/pages/' + $pageid + '/incidents/' + $cleanoutput.id +'.json'

            ##Define API Data
            $params = @{"incident[name]"="PLM Backup";
            "incident[status]"="verifying"; 
            "incident[component_ids][]"="$componentid";
            "incident[components][$componentid]"="operational";
            "incident[deliver_notifications]"="false";
            "incident[body]"="PLM services are now back up. The databases have been backed up, we are just now waiting for the file copies to complete.";
            }

            ##Invoke API to Update/Activate Incident
            $rawoutput = Invoke-WebRequest -Headers @{"Authorization" = "$oauth"} -Method PATCH `
                            -Uri $curlpost `
                            -ContentType application/x-www-form-urlencoded `
                            -Body $params
            #Take output from pipeline and convert to JSON (only the content returned from the Invoke)
            $cleanoutput = ConvertFrom-Json $rawoutput.Content
            #Store in file for Phase 4
            $cleanoutput | Export-CliXml c:\batch\statuspage\output.xml
        break
    }
    "4" {
        ##Phase 4 is invoked when copying is completed, this makes the maintenance job enter the "Completed" Phase
        Write-Host "Phase 4 is invoked when copying is completed, this makes the maintenance job enter the 'Completed' Phase"
        ##Read out data from Phase 3
        $cleanoutput = Import-CliXml c:\batch\statuspage\output.xml

        ##Define new URL with output
        $curlpost = 'https://api.statuspage.io/v1/pages/' + $pageid + '/incidents/' + $cleanoutput.id +'.json'

        ##Define API Data
        $params = @{"incident[name]"="PLM Backup";
        "incident[status]"="completed"; 
        "incident[component_ids][]"="$componentid";
        "incident[components][$componentid]"="operational";
        "incident[deliver_notifications]"="false";
        "incident[body]"="The daily PLM backup is complete.  All services should be normal.  Please contact the service desk if you continue to experince issues.";
        }

        ##Invoke API to Update/Activate Incident
        $rawoutput = Invoke-WebRequest -Headers @{"Authorization" = "$oauth"} -Method PATCH `
                        -Uri $curlpost `
                        -ContentType application/x-www-form-urlencoded `
                        -Body $params
        #Take output from pipeline and convert to JSON (only the content returned from the Invoke)
        $cleanoutput = ConvertFrom-Json $rawoutput.Content
        #Store in file for Phase2
        $cleanoutput | Export-CliXml c:\batch\statuspage\output.xml
        <# ##Phase 5 is optional and is invoked if you want to remove the incident from history

        ##Define Header Data
        $headers = "Authorization" = "OAuth $apikey"

        ##Invoke API to Delete
        Invoke-WebRequest -Headers @{$headers} -Method DELETE `
                        -Uri $curlurl `
                        -ContentType application/x-www-form-urlencoded `
                        -Body $params #>
        break
    }
    "*" {
        Write-Host "The entered phase is invalid"
        break
    }
 }
