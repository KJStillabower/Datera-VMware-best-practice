<#
         Datera VMware Best Practices Implementation Script
 
=====================================================================
|                          Disclaimer:                              |
| This scripts are offered "as is" with no warranty.  While this    |
| scripts is tested and working in my environment, it is            |
| recommended that you test this script in a test lab before using  |
| in a production environment. Everyone can use the scripts/commands|
| provided here without any written permission but I will not be    |
| liable for any damage or loss to the system.                      |
=====================================================================

Requirements:
1. PowerCLI connection to a Windows vCenter server that manages
   ESXi hosts that must have privileges to make changes to advanced
   settings
2. Before running, if you want to modify the configurations based on
   the this script, please make sure the ESXi hosts not connected
   to iSCSI target.  
#>


########
########  Parameters Section
########

Param([parameter(Mandatory=$false, HelpMessage="
     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
     !!  The script is used to disable ATS heartbeat and    !!
     !!  to change 3 iSCSI parameters globally on new       !!
     !!  ESXi hosts without datastore/storage.              !!
     !!    - Disable ATS Heartbeat                          !!
     !!    - Disable DelayedAck on software iSCSI adapter   !!
     !!    - Set iSCSI queue depth to 16                    !!
     !!    - Set Datera NMP SATP Rule to                    !!
     !!      VMW_PSP_RR and IOPS = 1                        !!
     !!                                                     !!
     !!  This may cause mis-function on ESXi hosts          !!
     !!  If you have sorage connected, it is your risk      !!
     !!  to update configuration of software iSCSI adapter  !!
     !!  via this script.                                   !!
     !!                                                     !! 
     !!  This script is offered `"as is`" with no warranty.   !!
     !!  I will not be liable for any damage or loss to     !!
     !!  the system if you run this script. You need to     !!
     !!  test on your platform and understand the script.   !!
     !!                                                     !!
     !!  If you agree to proceed, please enter `"Yes`" to     !!
     !!  update; otherwise enter `"No`" to only display       !!
     !!  the current setup.                                 !!
     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
   ")] [bool]$Update=$false,
   [parameter(Mandatory=$true,HelpMessage="
     This is the FQDN of the vCenter Server
     Examples:
        ""vcenter.contoso.com`" 
        vcenter.contoso.com
     ")] [string] $vCenterServer,
   [parameter(Mandatory=$false,HelpMessage="
    When set to true means script output tells user everything 
    that is happening throughout the script.
    If you want lighter feedback, enable the succinct flag.
")][bool] $verb = $false,
   [parameter(Mandatory=$false,HelpMessage="
    When set to true means the script will give you summary 
    output throughout the script.
    If you want more feedback, try the verbose flag.
")][bool] $succinct = $false,
[parameter(Mandatory=$false,HelpMessage="
    That means no confirmation received for the command to change 
    the advanced settings
")][bool] $Confirm = $false,
[parameter(Mandatory=$true,HelpMessage="
    This is the account that you will use to connect to vCenter")] 
    [PSCredential] $vCredential,
[parameter(Mandatory=$false,HelpMessage="
    Use this to keep from sending an email on each run of the script.  Great for debigging and fixing existing problem machines.
")] [bool] $SendEmail=$true,
[parameter(Mandatory=$false,HelpMessage="
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    !!                                                       !!
    !!                     #WARNING#                         !!
    !!  If set to true this script could disrupt a           !!
    !!  production environment. Proceed with caution.        !!
    !!                                                       !!
    !!  Setting this flag will force the system to ignore    !!
    !!  built-in logic checks but end up setting the correct !!
    !!  values to make the system optimal.                   !!
    !!                                                       !! 
    !!  By setting this flag you acknowledge this risk and   !!
    !!  do so against best-practice. You have read and       !!
    !!  understood the documentation.  This SHOULD work for  !!
    !!  most, but some may do harm to their environemnt.     !!
    !!                                                       !!
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
")] [bool]$iWantToLiveDangerously=$false)


########
########  Script Constants
########

## Storage Values

    $DateraIscsiQueueDepth = 16 #datera recommends 16

## Email

    $SMTP_RELAY = "RELAYSERVER.CORPORATE.INTERNAL"
    $SMTP_FROM = "DATERA@CORPORATE.COM"
    $SMTP_TO = "OPS_TEAM@CORPORATE.COM"
    

 

#####################
##### FUNCTIONS #####
#####################
         
function Email-Alert 
{
    param(
    [Parameter(Mandatory=$true)][String]$SMTP_RELAY,
    [Parameter(Mandatory=$true)][String]$SMTP_FROM,
    [Parameter(Mandatory=$true)][String]$To,
    [Parameter(Mandatory=$true)][String]$Subject,
    [Parameter(Mandatory=$true)][String]$Message,
    [Parameter(Mandatory=$false)][bool]$critical=0)

    if ($critical)
    {
        $Subject = "CRITICAL: $Subject"
    }

    $SendingServer = $SMTP_RELAY
    $From = $SMTP_FROM

    Send-MailMessage -BodyAsHtml -SmtpServer $SendingServer -To $To -From $from -Subject $Subject -Body $message
    
}

function Format-Color([hashtable] $Colors = @{}, [switch] $SimpleMatch) {
        $lines = ($input | Out-String) -replace "`r", "" -split "`n"
        foreach($line in $lines) {
                $color = ''
                foreach($pattern in $Colors.Keys) {
                        if(!$SimpleMatch -and $line -match $pattern) { $color = $Colors[$pattern] }
                        elseif ($SimpleMatch -and $line -like $pattern) { $color = $Colors[$pattern] }
                }
                if($color) {
                        Write-Host -ForegroundColor $color $line
                } else {
                        Write-Host $line
                }
        }
}
#########################
#### INLINE INCLUDES ####
#########################
## Code Type: Function
## Decription: Write the output of PSObjects with formatted defined colors with two ways.
##             The first way is to format the whole table to write the Odd lines with a specific fore/back colors, and the even with deferent ones.
##             The second way is to write a specific column's value or the whole line based on a condition or more for the output values.
## Author: Ahmad Gad
## Contact Email: ahmad.gad@jemmpress.com
## WebSite: http://ahmad.jempress.com
## Date Format: DD/MM/YYYY
## Created On: 01/12/2016
## Updated On: 21/12/2018
## PSVersion Supported: 2.0+

Function Write-PSObject
{
    <#
      .SYNOPSIS
      	Display the input PSObject(s)/Object(s) as formatted table with defined fore/back colors for headers row and/or body rows and/or columns values based on specified conditions or criteria.
      .DESCRIPTION
        Display the input PSObject(s)/Object(s) with formatted defined colors with three ways which could be combined together.
        The first way is to format the whole table to write the Odd lines with a specific fore/back colors, and the even with deferent ones.
        The second way is to write a specific column's value or the whole line based on a condition or more for the output values.
        The third way is to write a separator line between each two lines which could be blank line, or any other values with our without specified fore/back color.
      .EXAMPLE
        #In this example, the output lines will be colored with "Yellow" forecolor and "Blue" backcolor if any value inside that line exactly equals to "False" for any property.
        Write-PSObject -PSObject $psObjects -MatchMethod Exact -Column "*" -Value $False -RowForeColor Yellow -RowBackColor Blue;
      .EXAMPLE
        #In this example, the output lines will be colored with "Red" forecolor if any value inside that line exactly equals to "False" for any property.
        Write-PSObject -PSObject $psObjects -MatchMethod Exact -Column "*" -Value $False -RowForeColor Red;
      .PARAMETER Object
        Alias: O, I
        Data Type: Object
        Mandatory: True
        Description: The input PSOject(s) to display with formatted colors.
        Example(s): N/A
        Default Value: N/A
        Notes: N/A.
      .PARAMETER MatchMethod
        Alias: MM, M
        Data Type: String[]
        Mandatory: False
        Description: The array of values validations way which must be provided with one of the three valid set "Exact", "Match" or "Query".
        Example(s): N/A
        Default Value: N/A
        Notes:  If this parameter not provided, the conditional formatting will not be functional and all the tailed parameters will be ignored.
                This must be tailed with the following parameters to be functional:
               "Column", "Value" and one or more of the following parameters:
               "ValueForeColor", "ValueBackColor", "RowForeColor" and/or "RowBackColor".  
      .PARAMETER FormatTableColor
        Alias: FTC, FT, F
        Data Type: Switch
        Mandatory: False
        Description: If specified, lines will be formatted with specified fore/back colors based on the sequence.
                     User can define specific fore or/and back color for odd lines in sequence, and different fore or/and back colors for even lines.
        Example(s): N/A
        Default Value: N/A
        Notes: User needs to use one or more of the following parameters with this switch in order to make it functional:
               "OddLineForeColor", "OddLineBackColor", "EvenLineForeColor" and/or "EvenLineBackColor"
      .PARAMETER Column
        Alias: C, Col
        Data Type: String[]
        Mandatory: False
        Description: The list of the names of columns/properties which hold the value(s) to be validated to apply the table formatting.
        Example(s): N/A
        Default Value: *
        Notes: This parameter can provided as one string or array of them which must match the same count of the "Value" parameter or the script will be terminated (If the "$IgnoreErrors" switch is provided, the function will not be terminated, but the formatting will not be functional).
               If the parameter "MatchMethod" is not provided, this column and all the other relative ones will be ignored and the whole conditional formatting will not be functional.
               The "*" is referring to all the columns/properties within the table/PSObject(s).
               If the "*" is provided as a name of column/property, that means the same condition defined by the "MatchMethod" and "Value" parameters will be applied on all the columns/properties.
               For example, you can just mention "*" as column/property name to color all the "False" values for any column/property with  forecolor "Red" and/or backcolor "Black".
      .PARAMETER Value
        Alias: V
        Data Type: String[]
        Mandatory: False
        Description: The value validation way which must be matching with one of the following three valid set provided by the parameter "MatchMethod" (all case insensitive):
                     1. Exact ---» The provided value must match exactly with the inputs.
                                   Ex1: -Value "True"
                                   Ex2: -Value $True
                                   Ex3: -Value 4
                                   Ex4: -Value "Ahmad", 4, "True", $False
                     2. Match ---» The provided value must match with part of the inputs.
                                   Ex1: "Ahmad"
                                   Ex2: -Value "Ah"
                                   Ex3: -Value "ma"
                                   Ex4: -Value "ad"
                                   Ex5: -Value "X", "C123", "A"
                     3. Query ---» The provided value must match with the provided query which could contains various conditions on the same column.
                                   Ex1: -Value "'Up Time' -Like '00 Days*'"
                                   Ex2: -Value "'CPU' -gt 90 -and CPU -le 95'"
                                   Ex3: -Value "'Name' -Match 'C3' -and 'Name' -Notmatch 'C34'"
                                   Ex4: -Value "'Name' -Match 'C3' -and 'Name' -Notmatch 'C34'", "'Up Time' -Like '00 Days*'"
                                   Ex5: -Value "'Name' -Match 'Ahmad' -and 'Address' -Notmatch 'Central Park'", "'Up Time' -Like '00 Days*'"
                                   Please note that, column/property name must be put as it is between two single quotations, and the whole condition/query between two double quotations.
        Example(s): N/A
        Default Value: N/A
        Notes: This must be tailed with the following parameters to be functional:
               "Column", "Value" and one or more of the following parameters:
               "ValueForeColor", "ValueBackColor", "RowForeColor" and/or "RowBackColor".
               This parameter can provided as one string value or array of them which must match the same count of the "Column" parameter or the script will be terminated (If the "$IgnoreErrors" switch is provided, the function will not be terminated, but the formatting will not be functional).
               If the parameter "MatchMethod" is not provided, this column and all the other relative ones will be ignored and the whole conditional formatting will not be functional.
      .PARAMETER FormatTableColor
        Alias: FTC, FT, F
        Data Type: Switch
        Mandatory: False
        Description: If specified, lines will be formatted with specified fore/back colors based on the sequence.
                     User can define specific fore or/and back color for odd lines in sequence, and different fore or/and back colors for even lines.
        Example(s): N/A
        Default Value: N/A
        Notes: User needs to use one ore more of the following parameters with this switch in order to make it functional:
               "OddLineForeColor", "OddLineBackColor", "EvenLineForeColor" and/or "EvenLineBackColor"
      .PARAMETER ValueForeColor
        Alias: VFC
        Data Type: ConsoleColor[]
        Mandatory: False
        Description: Used to define the forecolor of the values that match the specified condition.
        Example(s): Red, Black, Blue, White, etc.
        Default Value: N/A
        Notes: This parameter is function only when the following parameters are provided "MatchMethod" “Column” and “Value”.
      .PARAMETER ValueBackColor
        Alias: VBC
        Data Type: ConsoleColor[]
        Mandatory: False
        Description: Used to define the backcolor of the values that match the specified condition.
        Example(s): Red, Black, Blue, White, etc.
        Default Value: N/A
        Notes: This parameter is function only when the following parameters are provided "MatchMethod" “Column” and “Value”.
      .PARAMETER RowForeColor
        Alias: RFC
        Data Type: ConsoleColor
        Mandatory: False
        Description: Used to define the forecolor of the whole line/row that when of its values match the specified condition(s).
                     With another meaning, if no values inside that row/line (single PSObject) matches any provided condition, this parameter will be ignored.
        Example(s): Red, Black, Blue, White, etc.
        Default Value: Null
        Notes: This parameter is function only when the "MatchMethod" parameter is provided.
               If the "ValueForeColor" is provided, it could override the colors of the matched properties values, if they match with specific provided condition(s).
               The "FlagsForeColor" of the flagged columns would override it.
      .PARAMETER RowBackColor
        Alias: RBC
        Data Type: ConsoleColor
        Mandatory: False
        Description: Used to define the backcolor of the whole line/row that any of its values match the specified condition(s).
                     With another meaning, if no values inside that row/line (single PSObject) matches any provided condition, this parameter will be ignored.
        Example(s): Red, Black, Blue, White, etc.
        Default Value: Null
        Notes: This parameter is function only when the "MatchMethod" parameter is provided.
               If the "ValueBackColor" is provided, it could override the colors of the matched properties values, if they match with specific provided condition(s).
               The "FlagsBackColor" of the flagged columns would override it.
      .PARAMETER OddLineForeColor
        Alias: OLFC
        Data Type: ConsoleColor
        Mandatory: False
        Description: Used to define the forecolor of the whole line/row that with an odd sequence of the whole rows starting from the first row of values.
                     Example, you can provide that parameter with the forecolor of the rows number 1, 3, 5, 7, etc.
        Example(s): Red, Black, Blue, White, etc.
        Default Value: The default forecolor of the host.
        Notes: This parameter is function only when the "FormatTableColor" parameter is provided.
               It can work with or without the other relative odd/even fore/back colors.
               If the "ValueForeColor" is provided, it could override the colors of the matched properties values, if they match with specific provided condition(s).
               If the "RowForeColor" is provided, it could override the color of the whole line/row, if they match with specific provided condition(s).
               The "FlagsForeColor" of the flagged columns would override it.
      .PARAMETER OddLineBackColor
        Alias: OLBC
        Data Type: ConsoleColor
        Mandatory: False
        Description: Used to define the backcolor of the whole line/row that with an odd sequence of the whole rows starting from the first row of values.
                     Example, you can provide that parameter with the backcolor of the rows number 1, 3, 5, 7, etc.
        Example(s): Red, Black, Blue, White, etc.
        Default Value: The default backcolor of the host.
        Notes: This parameter is function only when the "FormatTableColor" parameter is provided.
               It can work with or without the other relative odd/even fore/back colors.
               If the "ValueBackColor" is provided, it could override the colors of the matched properties values, if they match with specific provided condition(s).
               If the "RowBackColor" is provided, it could override the color of the whole line/row, if they match with specific provided condition(s).
               The "FlagsBackColor" of the flagged columns would override it.
      .PARAMETER EvenLineForeColor
        Alias: ELFC
        Data Type: ConsoleColor
        Mandatory: False
        Description: Used to define the forecolor of the whole line/row that with an even sequence of the whole rows starting from the second row of values.
                     Example, you can provide that parameter with the forecolor of the rows number 2, 4, 6, 8, etc.
        Example(s): Red, Black, Blue, White, etc.
        Default Value: The default forecolor of the host.
        Notes: This parameter is function only when the "FormatTableColor" parameter is provided.
               It can work with or without the other relative odd/even fore/back colors.
               If the "ValueForeColor" is provided, it could override the colors of the matched properties values, if they match with specific provided condition(s).
               If the "RowForeColor" is provided, it could override the color of the whole line/row, if they match with specific provided condition(s).
               The "FlagsForeColor" of the flagged columns would override it.
      .PARAMETER EvenLineBackColor
        Alias: ELBC
        Data Type: ConsoleColor
        Mandatory: False
        Description: Used to define the backcolor of the whole line/row that with an odd sequence of the whole rows starting from the second row of values.
                     Example, you can provide that parameter with the backcolor of the rows number 2, 4, 6, 8, etc.
        Example(s): Red, Black, Blue, White, etc.
        Default Value: The default backcolor of the host.
        Notes: This parameter is function only when the "FormatTableColor" parameter is provided.
               It can work with or without the other relative odd/even fore/back colors.
               If the "ValueBackColor" is provided, it could override the colors of the matched properties values, if they match with specific provided condition(s).
               If the "RowBackColor" is provided, it could override the color of the whole line/row, if they match with specific provided condition(s).
               The "FlagsBackColor" of the flagged columns would override it.
      .PARAMETER HeadersForeColor
        Alias: HFC
        Data Type: ConsoleColor
        Mandatory: False
        Description: Used to define the forecolor of the whole two headers lines/rows.
                     The first header row/line which describes the names of the columns/properties.
                     While, the second header row/line is the underlines dashes characters which separate the header names than the rows' values.
                     Example, When get the results of the function "Get-ChildItem -Path C:\ | FT -Al;", the output would be something like the following:
                     Mode             LastWriteTime Length Name   # First header line.
                     ----             ------------- ------ ----   # Second header line.
        Example(s): Red, Black, Blue, White, etc.
        Default Value: The default forecolor of the host.
        Notes: This parameter is not dependent on any other parameters or conditions.
      .PARAMETER HeadersBackColor
        Alias: HBC
        Data Type: ConsoleColor
        Mandatory: False
        Description: Used to define the backcolor of the whole two headers lines/rows.
                     The first header row/line which describes the names of the columns/properties.
                     While, the second header row/line is the underlines dashes characters which separate the header names than the rows' values.
                     Example, When get the results of the function "Get-ChildItem -Path C:\ | FT -Al;", the output would be something like the following:
                     Mode             LastWriteTime Length Name   # First header line.
                     ----             ------------- ------ ----   # Second header line.
        Example(s): Red, Black, Blue, White, etc.
        Default Value: The default backcolor of the host.
        Notes: This parameter is not dependent on any other parameters or conditions.
      .PARAMETER BodyForeColor
        Alias: BFC
        Data Type: ConsoleColor
        Mandatory: False
        Description: Used to define the forecolor of the whole lines/rows values.
        Example(s): Red, Black, Blue, White, etc.
        Default Value: The default forecolor of the host.
        Notes: This parameter is not dependent on any other parameters or conditions.
               If the "ValueForeColor" is provided, it could override the colors of the matched properties values, if they match with specific provided condition(s).
               If the "RowForeColor" is provided, it could override the color of the whole line/row, if they match with specific provided condition(s).
               If the "OddLineForeColor" and /or "EvenLineForeColor" parameter(s) are provided, they would override it.
               The "FlagsForeColor" of the flagged columns would override it.
      .PARAMETER BodyBackColor
        Alias: BBC
        Data Type: ConsoleColor
        Mandatory: False
        Description: Used to define the backcolor of the whole lines/rows values.
        Example(s): Red, Black, Blue, White, etc.
        Default Value: The default backcolor of the host.
        Notes: This parameter is not dependent on any other parameters or conditions.
               If the "ValueBackColor" is provided, it could override the colors of the matched properties values, if they match with specific provided condition(s).
               If the "RowBackColor" is provided, it could override the color of the whole line/row, if they match with specific provided condition(s).
               If the "OddLineBackColor" and /or "EvenLineBackColor" parameter(s) are provided, they would override it.
               The "FlagsBackColor" of the flagged columns would override it.
      .PARAMETER ColoredColumns
        Alias: CC
        Data Type: String[]
        Mandatory: False
        Description: Define the columns/properties to have their values colored without conditions.
        Example(s): "CPU", "Memory", "SN"
        Default Value: N/A
        Notes: This parameter is not dependent on any other parameters or conditions.
      .PARAMETER ColumnForeColor
        Alias: CFC
        Data Type: ConsoleColor[]
        Mandatory: False
        Description: Used to define the forecolor of values the specified "ColoredColumns".
        Example(s): Red, Black, Blue, White, etc.
        Default Value: N/A
        Notes: This parameter is function only when the "ColoredColumns" parameter is provided.
               If the "ValueForeColor" is provided, it could override the colors of the matched properties values, if they match with specific provided condition(s).
               If the "RowForeColor" is provided, it could override the color of the whole line/row, if they match with specific provided condition(s).
               If the "OddLineForeColor" and /or "EvenLineForeColor" parameter(s) are provided, they would override it.
               The "FlagsForeColor" of the flagged columns would override it.        
      .PARAMETER ColumnBackColor
        Alias: CBC
        Data Type: ConsoleColor[]
        Mandatory: False
        Description: Used to define the backcolor of the whole lines/rows values.
        Example(s): Red, Black, Blue, White, etc.
        Default Value: N/A
        Notes: This parameter is function only when the "ColoredColumns" parameter is provided.
               If the "ValueBackColor" is provided, it could override the colors of the matched properties values, if they match with specific provided condition(s).
               If the "RowBackColor" is provided, it could override the color of the whole line/row, if they match with specific provided condition(s).
               If the "OddLineBackColor" and /or "EvenLineBackColor" parameter(s) are provided, they would override it.
               The "FlagsBackColor" of the flagged columns would override it.           
      .PARAMETER FlagColumns
        Alias: FC
        Data Type: String[]
        Mandatory: False
        Description: Define the columns/properties to have their values colored when any of the specified values match the specified condition(s).
        Example(s): "CPU", "Memory", "SN"
        Default Value: N/A
        Notes: This parameter is function only when the following parameters are provided "MatchMethod" “Column” and “Value”.
      .PARAMETER FlagsForeColor
        Alias: FFC
        Data Type: ConsoleColor[]
        Mandatory: False
        Description: Used to define the forecolor of the flagged columns/properties.
        Example(s): Red, Black, Blue, White, etc.
        Default Value: N/A
        Notes: This parameter is function only when the ""MatchMethod" “Column”, “Value” and "FlagColumns" parameters are provided.
               If the "ValueForeColor" is provided, it could override the colors of the matched properties values, if they match with specific provided condition(s).
               This would override the colors specified by the "RowBackColor", "OddLineFBackColor" and/or the "EvenLineBackColor" parameters.

      .PARAMETER FlagsBackColor
        Alias: FBC
        Data Type: ConsoleColor[]
        Mandatory: False
        Description: Used to define the backcolor of the whole lines/rows values.
        Example(s): Red, Black, Blue, White, etc.
        Default Value: N/A
        Notes: This parameter is function only when the ""MatchMethod" “Column”, “Value” and "FlagColumns" parameters are provided.
               If the "ValueBackColor" is provided, it could override the colors of the matched properties values, if they match with specific provided condition(s).
               This would override the colors specified by the "RowForeColor", "OddLineForeColor" and/or the "EvenLineForeColor" parameters.
      .PARAMETER InjectRowsSeparator
        Alias: IRS
        Data Type: Switch
        Mandatory: False
        Description: If specified, new lines would be injected between body rows/lines.
        Example(s): N/A
        Default Value: N/A
        Notes: By default the new line separator would be just new line with null data as the default value of the "RowsSeparator" parameter is $null.
       .PARAMETER RowsSeparator
        Alias: RS
        Data Type: String
        Mandatory: False
        Description: Define the shape of the separator line/row between body rows/lines.
                     The value could be one character such as "-", "==", etc, or mixed ones and the line would be trimmed by the maximum length of the body rows.
        Example(s): "-", ".", "=", "|", "#", " ", etc.
        Default Value: $null
        Notes: This parameter is function only when the "InjectRowsSeparator"  parameter is provided.
               If not specified, the new line separator would be just new line with null data.
      .PARAMETER RowsSeparatorForeColor
        Alias: RSFC
        Data Type: ConsoleColor
        Mandatory: False
        Description: Used to define the forecolor of the separator rows/lines.
        Example(s): Red, Black, Blue, White, etc.
        Default Value: The default forecolor of the host.
        Notes: This parameter is function only when the "InjectRowsSeparator" and "RowsSeparator" parameters are provided.
      .PARAMETER RowsSeparatorBackColor
        Alias: RSBC
        Data Type: ConsoleColor
        Mandatory: False
        Description: Used to define the backcolor of the separator rows/lines.
        Example(s): Red, Black, Blue, White, etc.
        Default Value: The default backcolor of the host.
        Notes: This parameter is function only when the "InjectRowsSeparator" and "RowsSeparator" parameters are provided.
      .PARAMETER RemoveHeadersSeparator
        Alias: RHS
        Data Type: Switch
        Mandatory: False
        Description: Neglect displaying the second header line "----" (the separator line between headers (columns/properties) names and the body rows/values.).
                     With another meaning, the values rows/lines would be printed directly after the columns/properties names line/row.
        Example(s): N/A
        Default Value: N/A
        Notes: This parameter will not be functional if "BodyOnly" parameter is specified.
      .PARAMETER HeadersSeparator
        Alias: HS
        Data Type: String
        Mandatory: False
        Description: Define the shape of the separator header separator line "----" between the columns names and body rows.
                     The value could be one character such as ".", "==", etc, or mixed ones and the line would be trimmed by the maximum length of the body rows.
        Example(s): ".", "=", "|", "#", " ", etc.
        Default Value: "-"
        Notes: This parameter will not be functional if any of the two parameters "BodyOnly" or "RemoveHeadersSeparator" is specified.
      .PARAMETER HeadersSeparatorForeColor
        Alias: HSFC
        Data Type: ConsoleColor
        Mandatory: False
        Description: Used to define the forecolor of the separator header separator line "----" between the columns names and body rows.
        Example(s): Red, Black, Blue, White, etc.
        Default Value: The default forecolor of the host.
        Notes: This parameter will not be functional if any of the two parameters "BodyOnly" or "RemoveHeadersSeparator" is specified.
      .PARAMETER HeadersSeparatorBackColor
        Alias: HSBC
        Data Type: ConsoleColor
        Mandatory: False
        Description: Used to define the backcolor of the separator header separator line "----" between the columns names and body rows.
        Example(s): Red, Black, Blue, White, etc.
        Default Value: The default backcolor of the host.
        Notes: This parameter will not be functional if any of the two parameters "BodyOnly" or "RemoveHeadersSeparator" is specified.
      .PARAMETER BodyOnly
        Alias: BO
        Data Type: Switch
        Mandatory: False
        Description: If specified, only the body rows (values lines) will be displayed, and, the two headers lines will not be displayed.
        Example(s): N/A
        Default Value: N/A
        Notes: This parameter is not dependent on any other parameters or conditions.
      .PARAMETER HeadersOnly
        Alias: HO
        Data Type: Switch
        Mandatory: False
        Description: If specified, only the two headers lines will be displayed, and, the body rows (values lines) will not be displayed.
        Example(s): N/A
        Default Value: N/A
        Notes: This parameter is not dependent on any other parameters or conditions.
      .PARAMETER IgnoreErrors
        Alias: IE
        Data Type: Switch
        Mandatory: False
        Description: It would try to suppress and error/exception could be raised due to missing or non matched parameters and continue displaying the rows.
        Example(s): N/A
        Default Value: N/A
        Notes: This parameter is not dependent on any other parameters or conditions.
               If one of the provided conditions which is provided by the combination of the properties "MatchMethod",  "Column", "Value" and/or "FlagColumns" and/or their relative properties was not well provided, or mismatching, the "MatchMethod" property would be ignored and the conditional formatting will not be functional.
      .PARAMETER HostWindowWidth
        Alias: HWW
        Data Type: UInt16
        Mandatory: False
        Description: Resize the host PowerShell window with a new specified width before presenting the data.
        Example(s): N/A
        Default Value: N/A
        Notes: This parameter is not dependent on any other parameters or conditions.
               It would also resize the buffer width size with the same specified value if the current value is less than the new specified window width.
      .PARAMETER HostWindowHeight
        Alias: HWH
        Data Type: UInt16
        Mandatory: False
        Description: Resize the host PowerShell window with a new specified height before presenting the data.
        Example(s): N/A
        Default Value: N/A
        Notes: This parameter is not dependent on any other parameters or conditions.
               It would also resize the buffer height size with the same specified height if the current value is less than the new specified window height.
      .PARAMETER HostWindowForeColor
        Alias: HWFC
        Data Type: ConsoleColor
        Mandatory: False
        Description: Override the current forecolor of the host PowerShell with a new specified one before presenting the data.
        Example(s): N/A
        Default Value: N/A
        Notes: This parameter is not dependent on any other parameters or conditions.
      .PARAMETER HostWindowBackColor
        Alias: HWBC
        Data Type: ConsoleColor
        Mandatory: False
        Description: Override the current background color of the host PowerShell with a new specified one before presenting the data.
        Example(s): N/A
        Default Value: N/A
        Notes: This parameter is not dependent on any other parameters or conditions.             
    #> 

    [CmdletBinding()]
    [OutputType("Void")]
    Param
    (
        [Parameter(Mandatory=$True,  Position= 0, ValueFromPipeline=$True, ValueFromPipelineByPropertyName=$True)][Alias("O", "I")][Object]$Object,
        [Parameter(Mandatory=$False, Position= 1)][Alias("MM", "M")] [String[]][ValidateSet("Exact","Match","Query")]$MatchMethod,
        [Parameter(Mandatory=$False, Position= 2)][Alias("FTC", "FT", "F")] [Switch]$FormatTableColor,
        [Parameter(Mandatory=$False, Position= 3)][Alias("C")] [String[]]$Column = "*",
        [Parameter(Mandatory=$False, Position= 4)][Alias("V")]  [String[]]$Value,
        [Parameter(Mandatory=$False, Position= 5)][Alias("VFC")][ConsoleColor[]]$ValueForeColor,
        [Parameter(Mandatory=$False, Position= 6)][Alias("VBC")][ConsoleColor[]]$ValueBackColor,
        [Parameter(Mandatory=$False, Position= 7)][Alias("RFC")][ConsoleColor]$RowForeColor,
        [Parameter(Mandatory=$False, Position= 8)][Alias("RBC")] [ConsoleColor]$RowBackColor,
        [Parameter(Mandatory=$False, Position= 9)][Alias("OLFC")] [ConsoleColor]$OddRowForeColor = (Get-Host).UI.RawUI.ForegroundColor,
        [Parameter(Mandatory=$False, Position=10)][Alias("OLBC")] [ConsoleColor]$OddRowBackColor = (Get-Host).UI.RawUI.BackgroundColor,
        [Parameter(Mandatory=$False, Position=11)][Alias("ELFC")] [ConsoleColor]$EvenRowForeColor = (Get-Host).UI.RawUI.ForegroundColor,
        [Parameter(Mandatory=$False, Position=12)][Alias("ELBC")] [ConsoleColor]$EvenRowBackColor = (Get-Host).UI.RawUI.BackgroundColor,
        [Parameter(Mandatory=$False, Position=13)][Alias("HFC")] [ConsoleColor]$HeadersForeColor = (Get-Host).UI.RawUI.ForegroundColor,
        [Parameter(Mandatory=$False, Position=14)][Alias("HBC")] [ConsoleColor]$HeadersBackColor = (Get-Host).UI.RawUI.BackgroundColor,
        [Parameter(Mandatory=$False, Position=15)][Alias("BFC")] [ConsoleColor]$BodyForeColor = (Get-Host).UI.RawUI.ForegroundColor,
        [Parameter(Mandatory=$False, Position=16)][Alias("BBC")] [ConsoleColor]$BodyBackColor = (Get-Host).UI.RawUI.BackgroundColor,      
        [Parameter(Mandatory=$False, Position=17)][Alias("CC")] [String[]]$ColoredColumns,
        [Parameter(Mandatory=$False, Position=18)][Alias("CFC")] [ConsoleColor[]]$ColumnForeColor,
        [Parameter(Mandatory=$False, Position=19)][Alias("CBC")] [ConsoleColor[]]$ColumnBackColor,
        [Parameter(Mandatory=$False, Position=20)][Alias("FC")] [String[]]$FlagColumns,
        [Parameter(Mandatory=$False, Position=21)][Alias("FFC")] [ConsoleColor[]]$FlagsForeColor,
        [Parameter(Mandatory=$False, Position=22)][Alias("FBC")] [ConsoleColor[]]$FlagsBackColor,
        [Parameter(Mandatory=$False, Position=23)][Alias("IRS")] [Switch]$InjectRowsSeparator,
        [Parameter(Mandatory=$False, Position=24)][Alias("RS")] [String]$RowsSeparator = $null,
        [Parameter(Mandatory=$False, Position=25)][Alias("RSFC")] [ConsoleColor]$RowsSeparatorForeColor = (Get-Host).UI.RawUI.ForegroundColor,
        [Parameter(Mandatory=$False, Position=26)][Alias("RSBC")] [ConsoleColor]$RowsSeparatorBackColor = (Get-Host).UI.RawUI.BackgroundColor,
        [Parameter(Mandatory=$False, Position=27)][Alias("RHS")] [Switch]$RemoveHeadersSeparator,        
        [Parameter(Mandatory=$False, Position=28)][Alias("HS")] [String]$HeadersSeparator = "-",
        [Parameter(Mandatory=$False, Position=29)][Alias("HSFC")] [ConsoleColor]$HeadersSeparatorForeColor = (Get-Host).UI.RawUI.ForegroundColor,
        [Parameter(Mandatory=$False, Position=30)][Alias("HSBC")] [ConsoleColor]$HeadersSeparatorBackColor = (Get-Host).UI.RawUI.BackgroundColor,                        
        [Parameter(Mandatory=$False, Position=31)][Alias("BO")] [Switch]$BodyOnly,
        [Parameter(Mandatory=$False, Position=32)][Alias("HO")] [Switch]$HeadersOnly,
        [Parameter(Mandatory=$False, Position=33)][Alias("IE")] [Switch]$IgnoreErrors,
        [Parameter(Mandatory=$False, Position=34)][Alias("HWW")] [UInt16]$HostWindowWidth,
        [Parameter(Mandatory=$False, Position=35)][Alias("HWH")] [UInt16]$HostWindowHeight,
        [Parameter(Mandatory=$False, Position=36)][Alias("HWFC")] [ConsoleColor]$HostWindowForeColor,
        [Parameter(Mandatory=$False, Position=37)][Alias("HWBC")] [ConsoleColor]$HostWindowBackColor
    )
    
    Function Write-Line
    {
        [CmdletBinding()]
        [OutputType("Void")]
        Param
        (
            [Parameter(Mandatory=$True,  Position= 0, ValueFromPipeline=$True, ValueFromPipelineByPropertyName=$True)][Alias("O", "I")][object]$Object,
            [Parameter(Mandatory=$False, Position= 1)][Alias("F", "FC")] [ConsoleColor]$ForegroundColor = (Get-Host).UI.RawUI.ForegroundColor,
            [Parameter(Mandatory=$False, Position= 2)][Alias("B", "BC")] [ConsoleColor]$BackgroundColor = (Get-Host).UI.RawUI.BackgroundColor,
            [Parameter(Mandatory=$False, Position= 3)][Alias("NNL")] [Switch]$NoNewline
        )

        If (([int]$ForegroundColor) -eq -1)
        {
            $ForegroundColor = [ConsoleColor]::White;
        }

        If (([int]$BackgroundColor) -eq -1)
        {
            Write-Host -NoNewline:$NoNewline -ForegroundColor $ForegroundColor -Object $Object;
        }
        Else
        {
            Write-Host -NoNewline:$NoNewline -ForegroundColor $ForegroundColor -BackgroundColor $BackgroundColor -Object $Object;
        }
    }

    If(($HostWindowWidth -And $HostWindowWidth -ne 0) -Or ($HostWindowHeight -And $HostWindowHeight -ne 0) -OR $HostWindowForeColor -ne $null -Or $HostWindowBackColor  -ne $null)
    {
        Try
        {
            $psHost = Get-Host;
            $psWindow = $psHost.UI.RawUI;

            If($HostWindowForeColor -ne $null -Or $HostWindowBackColor -ne $null)
            {
                If ($HostWindowBackColor -ne $null)
                {
                    $psWindow.BackgroundColor = $HostWindowBackColor;
                    $RowBackColor = $HostWindowBackColor;
                    $OddRowBackColor = $HostWindowBackColor;
                    $EvenRowBackColor = $HostWindowBackColor;
                    $HeadersBackColor = $HostWindowBackColor;
                    $BodyBackColor = $HostWindowBackColor;  
                    $ColumnBackColor = $HostWindowBackColor;
                    $FlagsBackColor = $HostWindowBackColor;
                    $RowsSeparatorBackColor = $HostWindowBackColor;
                    $HeadersSeparatorBackColor = $HostWindowBackColor;
                }

                If ($HostWindowForeColor -ne $null)
                {
                    $psWindow.ForegroundColor = $HostWindowForeColor;

                    $RowForeColor = $HostWindowForeColor;
                    $OddRowForeColor = $HostWindowForeColor;
                    $EvenRowForeColor = $HostWindowForeColor;
                    $HeadersForeColor = $HostWindowForeColor;
                    $BodyForeColor = $HostWindowForeColor;  
                    $ColumnForeColor = $HostWindowForeColor;
                    $FlagsForeColor = $HostWindowForeColor;
                    $RowsSeparatorForeColor = $HostWindowForeColor;
                    $HeadersSeparatorForeColor = $HostWindowForeColor;
                }
            }

            $newBufferSize = $psWindow.BufferSize;

            If ($HostWindowHeight -ne $null -And $HostWindowHeight -ne 0)
            {
                If ($newBufferSize.Height -lt $HostWindowHeight)
                {
                    $newBufferSize.Height = $HostWindowHeight;
                }
            }

            If ($HostWindowWidth -ne $null -And $HostWindowWidth -ne 0)
            {
                If ($newBufferSize.Width -lt $HostWindowWidth)
                {
                    $newBufferSize.Width = $HostWindowWidth;
                }
            }

            $psWindow.BufferSize = $newBufferSize;

            $newSize = $psWindow.WindowSize;

            If ($HostWindowHeight -ne $null -And $HostWindowHeight -ne 0)
            {
                $newSize.Height = $HostWindowHeight;
            }

            If ($HostWindowWidth -ne $null -And $HostWindowWidth -ne 0)
            {
                $newSize.Width = $HostWindowWidth;
            }
            
            If(($HostWindowWidth -ne $null -And $HostWindowWidth -ne 0) -Or ($HostWindowHeight -ne $null -And $HostWindowHeight -ne 0))
            {
                $psWindow.WindowSize = $newSize;
            }
        }
        Catch{}
    }

    $lines = (($input | FT -A | Out-String) -replace "`r", "" -split "`n") | ? {$_.Trim() -ne ""};
    If(!($lines))
    {
        $lines = (($Object | FT -A | Out-String) -replace "`r", "" -split "`n") | ? {$_.Trim() -ne ""};
    }
    else
    {
        $Object = $input;
    }

    If(!($lines) -Or $lines.Length -eq 0)
    {
        Return;
    }

    If($MatchMethod)
    {
        If(($Column.Count -ne $Value.Count))
        {
            If ($IgnoreErrors)
            {
                $MatchMethod = $False;
            }
            else
            {
                Write-Host "The count of the input columns seems not matching with the count of the input values or values' forecolors.";
                Return;
            }
        }

        If ($MatchMethod.Count -lt $Column.Count)
        {
            $MatchMethod = @($MatchMethod[0]) * $Column.Count;
        }
    }
    else
    {
        $Column = @();
        $FlagColumns = @();
    }

    #region Set Default Colors
    #region Defaults
 
    #endregion Defaults
    #region Match Method 
    If ($RowForeColor -eq -1)
    {
        $RowForeColor = $BodyForeColor;
    }
    
    If ($RowBackColor -eq -1)
    {
        $RowBackColor = $BodyBackColor;
    }
    #endregion Match Method

    #region Flag Columns
    If($FlagColumns.Count -gt 0)
    {
        If ($FlagColumns.Count -gt $FlagsForeColor.Count -and $FlagsForeColor.Count -ne 0)
        {
            $FlagsForeColor = @($FlagsForeColor[0]) * $FlagColumns.Count;
        }

        If ($FlagColumns.Count -gt $FlagsBackColor.Count -and $FlagsBackColor.Count -ne 0)
        {
            $FlagsBackColor = @($FlagsBackColor[0]) * $FlagColumns.Count;
        }
    }

    If($ColoredColumns.Count -gt 0)
    {
        If ($ColoredColumns.Count -gt $ColumnForeColor.Count -and $ColumnForeColor.Count -ne 0)
        {
            $ColumnForeColor = @($ColumnForeColor[0]) * $ColoredColumns.Count;
        }

        If ($ColoredColumns.Count -gt $ColumnBackColor.Count -and $ColumnBackColor.Count -ne 0)
        {
            $ColumnBackColor = @($ColumnBackColor[0]) * $ColoredColumns.Count;
        }
    }
    #endregion Flag Columns
    #endregion Set Default Colors
        
    $l = 0;
    Foreach($line in $lines) 
    {
        $l++;

        If($l -le 2)
        {
            If($l -eq 2 -And ($MatchMethod -Or $ColoredColumns))
            {
                $headerLine = $line;
                $header = $lines[0];
                [String[]]$headerLines = $headerLine -split " " | ? {$_.Trim() -ne ""} | Foreach {$_.Trim("`t").Trim();};
                $colCount = $headerLines.Count;
                $columns = @($null) * $colCount;
                
                [Int[]] $headersPos = @(0) * $colCount;
                [Int[]] $headersLen = @(0) * $colCount;
                
                $pos = 0;
                $i = 0;
                $headersPos[$i] = 0;
              
                $columns[$i] = $header.Substring($pos, $headerLines[$i].Length);
                $col = $Columns[$i];
                $headersLen[$i] = $object | Select $col, @{Name="Len";Expression={$_.$col.ToString().Length}} | Sort Len -Descending | Select Len -First 1 -ExpandProperty Len;
                If ($headerLines[$i].Length -gt $headersLen[$i])
                {
                    $headersLen[$i] = $headerLines[$i].Length;
                }

                While($pos -ne -1)
                {
                    $i++;
                    $pos = $headerLine.IndexOf(" -", $pos + 1, [System.StringComparison]::InvariantCultureIgnoreCase);
                    If($pos -eq -1)
                    {
                        Break;
                    }
                
                    $columns[$i] = $header.Substring($pos + 1, $headerLines[$i].Length);
                    $col = $Columns[$i];
                    $colLen = $object | Select $col, @{Name="Len";Expression={$_.$col.ToString().Length}} | Sort Len -Descending | Select Len -First 1 -ExpandProperty Len;
                    If ($col.Length -gt $colLen)
                    {
                        $colLen = $col.Length;
                    }

                    $headersLen[$i] = $colLen;
                    $headersPos[$i] = $headersPos[$i - 1]  + $headersLen[$i - 1] + 1; 
                }     
            }

            If ($l -eq 2 -And $RemoveHeadersSeparator)
            {
                Continue;
            }

            If(!($BodyOnly))
            {
                $hfc = $HeadersForeColor;
                $hbc = $HeadersBackColor;

                If($l -eq 2)
                {
                    If ($HeadersSeparator -ne "-")
                    {
                        If(!($HeadersSeparator))
                        {
                            $line = $null;
                        }
                        else
                        {
                            $line = $line.Replace("-", $HeadersSeparator);
                            $line = $line.Substring(0, $lines[0].Length);
                        }

                        $hfc = $HeadersSeparatorForeColor;
                        $hbc = $HeadersSeparatorBackColor;
                    }  
                }

                Write-Line -Object $line -ForegroundColor $hfc -BackgroundColor $hbc;
            }

            If($l -eq 2)
            {
                If($HeadersOnly)
                {
                    Return;
                }
            }

            Continue;
        }
        elseIf($l -gt 2  -And ($MatchMethod -Or $ColoredColumns))
        {
            $oLine = $object[$l -3];
            $values = @($null) * $colCount;

            For($i = 0; $i -lt $colCount; $i++)
            {
                $col = $Columns[$i];
                $values[$i] = $oLine | Select -ExpandProperty $col;
            }
        }

        If($FormatTableColor)
        {
            If($l % 2 -eq 0)
            {
                $BodyForeColor = $EvenRowForeColor;
                $BodyBackColor = $EvenRowBackColor;
            }
            else
            {
                $BodyForeColor = $OddRowForeColor;
                $BodyBackColor = $OddRowBackColor;
            }
        }

        $fc = @($BodyForeColor) * $colCount;
        $bc = @($BodyBackColor) * $colCount;

        If ($ColoredColumns)
        {
            For($j = 0; $j -lt $columns.Count; $j++)
            {
                If ($ColoredColumns -contains $columns[$j])
                {
                    $fColIndex = [System.Array]::IndexOf(($ColoredColumns | Foreach {$_.ToLower()}), $columns[$j].ToLower());
                    
                    If($fColIndex -lt $ColumnForeColor.Count)
                    {
                        $fc[$j] = $ColumnForeColor[$fColIndex];
                    }
                    
                    If($fColIndex -lt $ColumnBackColor.Count)
                    {
                        $bc[$j] = $ColumnBackColor[$fColIndex];
                    }
                }
            }
        }

        If($MatchMethod -Or $ColoredColumns)
        {
            $matchCond = $false;
            $matchCondGroup = @($false) * $Column.Count;
            $matchColumnFlag = @($false) * $columns.Count;
            For($i = 0; $i -lt $columns.Count; $i++)
            { 
                For($j = 0; $j -lt $Column.Count; $j++)
                {
                    $colPos = $null;
                    $colVal = $null;
                    $col = $Column[$j];
                    $val = $Value[$j];
                
                    If ($col -eq $columns[$i] -Or $col -eq "*")
                    {
                        $colPos = $i;
                        $colVal = $values[$i];
                        $query = $null;
                        $r = $null;
                        Switch ($MatchMethod[$j])
                        {
                            "Exact" {$query = """$colVal"" -eq ""$val"""};
                            "Match" {$query = """$colVal"" -match ""$val"""};
                            "Query" 
                            {
                                For($c = 0; $c -lt $columns.Count; $c++)
                                {
                                    $colC = $Columns[$c];
                                    $valC = $values[$c];
                                    [double]$valCNum = New-Object System.Double;
                                    $isNum = [double]::TryParse($valC, [ref] $valCNum);
                                    if($isNum)
                                    {
                                        $val = $val -replace "'$colC'" , "$valC";
                                    }
                                    else
                                    {
                                        $val = $val -replace "'$colC'" , "'$valC'";
                                    }
                                    $query = $val;
                                }
                            };
                        }
            
                        $r = Invoke-Expression $query;
                        If ($r)
                        {
                            $matchCond = $true;
                            If($ValueForeColor -ne $null -and $ValueForeColor.Count -gt $j)
                            {
                                $fColor = $ValueForeColor[$j]
                            }
                            elseIf($RowForeColor)
                            {
                                $fColor = $RowForeColor;
                            }
                            else
                            {
                                $fColor = $BodyForeColor;
                            }

                            If($ValueBackColor -ne $null -and $ValueBackColor.Count -gt $j)
                            {
                                $bColor = $ValueBackColor[$j]
                            }
                            elseIf($RowBackColor)
                            {
                                $bColor = $RowBackColor;
                            }
                            else
                            {
                                $bColor = $BodyBackColor;
                            }

                            $fc[$i] = $fColor;
                            $bc[$i] = $bColor;

                            $matchCondGroup[$j] = $True;
                            $matchColumnFlag[$i] = $True;
                            If($FlagColumns -ne $null -and $FlagColumns.Count -gt $j -and $FlagColumns[$j] -ne $null -and $FlagColumns[$j].Trim() -ne "")
                            {
                                [String[]]$fColumnsSplit = @();
                                $fColumnsSplit = $FlagColumns[$j] -split "," | ? {$_.Trim() -ne ""} | Foreach {$_.Trim("").Trim("'");};
                                
                                Foreach($fcs  in $fColumnsSplit)
                                {
                                    $fColIndex = [System.Array]::IndexOf(($columns | Foreach {$_.ToLower()}), $fcs.ToLower());
                                    If($fColIndex -ne -1)
                                    {
                                        If($j -lt $FlagsForeColor.Count)
                                        {
                                            $matchColumnFlag[$fColIndex] = $True;
                                            $fc[$fColIndex] = $FlagsForeColor[$j];
                                        }

                                        If($j -lt $FlagsBackColor.Count)
                                        {
                                            $matchColumnFlag[$fColIndex] = $True;
                                            $bc[$fColIndex] = $FlagsBackColor[$j];
                                        }
                                    }
                                }
                            }
                        }   
                    }
                }
            }

            For($j = 0; $j -lt $columns.Count; $j++)
            {
                $foreColor = $fc[$j];
                $backColor = $bc[$j];

                If ($matchCond)
                {
                    If (!($matchColumnFlag[$j]))
                    {
                        If ($RowForeColor -ne $null)
                        {
                            $foreColor = $RowForeColor;
                        }

                        If ($RowBackColor -ne $null)
                        {
                            $backColor = $RowBackColor;
                        }
                    }
                }
                 
                If ($j -eq 0)
                {
                    $vPos = $headersPos[$j];
                    $vLen = $headersLen[$j];
                }
                else
                {
                    If ($RowBackColor -ne $null -and $matchCond)
                    {
                        Write-Line " " -NoNewline -BackgroundColor $RowBackColor;
                    }
                    else
                    {
                        Write-Line " " -NoNewline -BackgroundColor $BodyBackColor;
                    }

                    $vPos = $headersPos[$j];
                    $vLen = $headersLen[$j];
                }

                $valueText = $line.SubString($vPos, $vLen);
                Write-Line -Object $valueText -NoNewline -ForegroundColor $foreColor -BackgroundColor $backColor;
                If ($j -eq $columns.Count - 1)
                {
                    Write-Host;     
                }
            } 
        }
        ElseIf(!($HeadersOnly))
        {
            Write-Line -ForegroundColor $BodyForeColor -BackgroundColor $BodyBackColor $line;
        }

        If ($l -ne ($lines.Length))
        {
            If ($InjectRowsSeparator)
            {
                If (!$RowsSeparator)
                {
                    $RowsSeparator = " ";
                }

                $RowsSeparatorLine =  $RowsSeparator * $line.Length;
                $RowsSeparatorLine = $RowsSeparatorLine.Substring(0, $line.Length);

                Write-Line -Object $RowsSeparatorLine -ForegroundColor $RowsSeparatorForeColor -BackgroundColor $RowsSeparatorBackColor;
            }
        }
    }
}

#######################################################
#######################################################
################### SCRIPT START ######################
#######################################################
#######################################################

Write-Host "
         
                .I%%%%7.                
              ~%%%%%%%%%%=.             
          .,%%%%%%%%7%%%%%%%.           
       ..%%%%%%%%%%%  ..%%%%%%%..       
    ..7%%%%%%%%%%%%%     .:%%%%%%%.     
   .%%%%%%%%%%%%%%%%        .?%%%%%%    
   %%%%%%%%%%%%%%%%%           .%%%%%   
  .%%%%%%%%%%%%%%%%%             .%%%.  
  .%%%%%%%%%%%%%%%%%             .%%%.  
  .%%%%%%%%%%%%%%%%%             .%%%.  
  .%%%%%%%%%%%%%%%%%             .%%%.  
  .%%%%%%%%%%%%%%%%%             .%%%.  
  .%%%%%%%%%%%%%%%%%             .%%%.  
  .%%%%%%%%%%%%%%%%%             .%%%.  
  .%%%%%%%%%%%%%%%%%             .%%%.  
  .%%%%%%%%%%%%%%%%%            .%%%%.  
   ,%%%%%%%%%%%%%%%%         .%%%%%%~   
    .:%%%%%%%%%%%%%%      .I%%%%%%~.    
        I%%%%%%%%%%%    .%%%%%%I.       
          .%%%%%%%%% .%%%%%%%.          
            ..%%%%%%%%%%%%..            
               .,%%%%%%:.               
                  ..~,.   

       SOFTWARE DEFINED EVERYTHING
       " -ForegroundColor Cyan
Write-Host "      Datera® VMware® Best Practices 
          Configuration Script
          "
$verbose = $verb

if ($vCredential -eq $null)
{
    $vCredential = Get-Credential -Message "$vCenterServer"
}

    
Write-Host "Connecting to vCenter..."
$list = Connect-VIServer $vCenterServer -Credential $vCredential 
if ($list -eq $null){
    Write-Host "Could not connect to vCenter at $vCenterServer." -ForegroundColor Red
    return
}
        
$vCenter = $global:DefaultVIServer     

Write-Host -ForegroundColor Green "Successfully connected to $($vCenter.Name) as $($vCenter.User)."


## Before you run this script, you have to make sure all ESXi hosts 
## must be actively managed by vCenter server.  
$vmhosts = Get-VMhost 

####
## Setup our results table for output
####

$results = $vmhosts | Select-Object Name

$results | add-member –membertype NoteProperty –name Connection_State –Value NotSet
$results | add-member -MemberType NoteProperty -name Reboot_Required -value No
$results | add-member –membertype NoteProperty –name Found_ATS_HB –Value NotSet
$results | add-member –membertype NoteProperty –name Found_Queue_Depth –Value NotSet
$results | add-member –membertype NoteProperty –name Found_Delayed_Ack -Value NoAdaptorPresent
$results | add-member –membertype NoteProperty –name Found_NMP_SATP_Rule –Value NotSet
$results | add-member -memberType NoteProperty -Name Opt_Status -Value Unknown

########    
########   SCRIPT START
########


$safeHosts = @()
if($verbose -eq $true){
    Write-Host ("====== List current ESXi hosts managed by vCenter ======")
    $vmhosts 
    Write-Host (" ")
}

# If we are updating...
if ($Update -eq $true) {
    # Warning 
    if ($verbose -or $succinct){
         Write-Host "
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    !!                                                       !!
    !! This part of the script does not run on the ESXi      !!
    !! hosts that have iSCSI targets or are not in           !!
    !! maintenacne mode in case you run this script by       !!
    !! mistake                                               !!
    !!                                                       !!" -ForegroundColor Green
Write-Host -ForegroundColor Red "    !!                     #WARNING#                         !!
    !!  Running this section could disrupt a production      !!
    !!  environment. Proceed with caution.                   !!" 
Write-Host -ForegroundColor Green "    !!                                                       !!
    !! You can:                                              !!
    !! 1.  Remove iSCSI targets from dynamic discovery and   !!
    !!     static target, removing the iSCSI targets will    !!
    !!     cause your ESXi datastore misfunction. You need   !!
    !!     to know what you're doing and risks               !!
    !!     Re-run this script again after removing them      !!
    !!                                                       !! 
    !! 2.  If you really want to run this script despite     !!
    !!     this safety check, you can acknowledge this risk  !!
    !!     by adding a switch at runtime to show that you    !!
    !!     have read the documentation and understand that   !!
    !!     this script may due harm to your environemnt.     !!"
Write-Host -ForegroundColor Red "    !!                                                       !!
    !!           -iWantToLiveDangerously:`$true               !!  
    !!                                                       !!"
Write-Host -ForegroundColor Green "    !! If you are seeing this message despite entering this  !!
    !! switch, you would know that the script will pause     !!
    !! here for 20 seconds just in case you didn't want to   !!
    !! to run the script and did so by accident              !!
    !!                                                       !!
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

    "
}

    Write-Host "Sleeping 20 seconds..." 
    Start-Sleep -Seconds 20

    # Determine which hosts are safe
    if ($verbose -or $succinct){Write-Host "
Determining which hosts are safe to update."}
    foreach($esx in $vmhosts){
    

        if ($succinct)
        { Write-Host "Checking $($esx.name)..."}
        if ($esx.ConnectionState -eq "Maintenance" -or $iWantToLiveDangerously)
        {
            $safeHosts += $esx
            if ($verbose) {Write-Host "$($esx.name) is in Maintenance or you want to live dangerously"}
            continue
        }
        if ($verbose) {Write-Host "$($esx.name) is not in Maintenance Mode. Checking iSCSI Adapters..."}
        $IscsiHba = $esx | Get-VMHostHba -Type iScsi | Where {$_.Model -eq "iSCSI Software Adapter"}
        if ($IscsiHba -eq $null)
        {
            $safeHosts += $esx
            if ($verbose) {Write-Host "$($esx.name) has no iSCSI adapter, it's safe, but need to configure manually" -ForegroundColor Yellow}
            continue   
        }
        $IscsiTarget = Get-IScsiHbaTarget -IScsiHba $IscsiHba
        if ($IscsiTarget -eq $null) {
            $safeHosts += $esx
            if ($verbose) {Write-Host "$($esx.name) has no targets. Adding to safe list" -ForegroundColor Yellow}
        }
        else
        {
            if ($verbose) {Write-Host "iSCSI Targets found, $($esx.Name) is unsafe."}
        }

    }
    if ($succinct) { Write-Host "
Identified $($safehosts.Count) hosts available to update.
"}
}

if ($verbose -or $succinct){  
    Write-Host "This script will: 
 - Disable ATS heartbeat on all ESXi hosts, otherwise iSCSI will misfunction
 - Set up iSCSI Queue Depth to be optimal per recommendation
 - Turn Off DelayedAck for improved performance in virtual Workloads
 - Set the NMP SATP Rule for optimal default datastore creation
"
}


if ($verbose -eq $true){
Write-Host -ForegroundColor Green "

########
######## Looping through all ESXi hosts
########
 
" 
}

foreach ($esx in $vmhosts)
{
    $index = $vmhosts.IndexOf($esx)
    $results.Item($index).Connection_State = $esx.ConnectionState
    if ($esx.ConnectionState -ne "NotResponding"){
        $results.Item($index).Opt_Status = "Optimal"
        if ($verbose -eq $true -or $succinct -eq $true){
            Write-Host ("########## " + $esx.Name + " ##########") -ForegroundColor Magenta
            Write-Host ("  ")
        }


########
########    Item 1: ATS heartbeat
########
##    Disable ATS Heartbeat on each ESXi host
##    Alternate method of implementation:
##        esxcli system settings advanced set -i 0 -o /VMFS3/UseATSForHBOnVMFS5
##
##    For details, please refer to https://kb.vmware.com/s/article/2113956#>
########

        if ($verbose) {Write-Output ("==== ATS heartbeat on " + $esx.Name + " (1:enabled 0:disabled) " + " ====")}
        $setting = Get-AdvancedSetting -Entity $esx -Name VMFS3.UseATSForHBOnVMFS5
        $results.Item($index).Found_ATS_HB = $setting.Value
        if ($verbose) 
        {
            $setting | Format-List | Format-Color @{"Value\s*:\s*1$" = 'Red'; "Value\s*:\s*0" = 'Green'}
        }
        if ($setting.value -eq 1)
        {
            if ($succinct) {Write-Host -ForegroundColor Red "DANGER: ATS For Heartbeat is On."}
            $results.Item($index).Opt_Status = "Critical"
            if ($safeHosts.Contains($esx))
            {
                if ($verbose -or $succinct){Write-Host "Identified this as a safe host to fix automatically, Attempting fix."}
                $results.item($index).Reboot_Required = "Yes"
                $setChange = Get-AdvancedSetting -Entity $esx -Name VMFS3.UseATSForHBOnVMFS5 | Set-AdvancedSetting -Value 0 -Confirm:$false
                if ($verbose -or $succinct){
                    if ($setChange.Value -eq 0)
                    {
                        Write-Host "Fix successful." -ForegroundColor Green
                        $results.Item($index).Found_ATS_HB = $setChange.Value
                    }
                    else
                    {Write-Host "Fix Failed." -foregroundColor Red }
                    Write-Host -ForegroundColor Cyan "You will need to reboot this host."
                }
            }
        }
        elseif ($succinct -eq $true) 
        {
            Write-Host -ForegroundColor Green "ATS for Heartbeat on VMFS 5 Disabled."
        }  
       

########
########    Item 2: Queue Depth    
########
##
##  Set Queue Depth for Software iSCSI initiator to 16
##  Default value is 128 or 256
##  Datera recommended value is 16
##  Alternate method of implementation:
##      esxcli system module parameters set -m iscsi_vmk -p iscsivmk_LunQDepth=16
##
##  Check the command result:
##      esxcli system module parameters list -m iscsi_vmk | grep iscsivmk_LunQDepth
########

        if ($verbose -eq $true){ Write-Output ("==== iSCSI Queue depth on " + $esx.Name + " ====")}
        $esxcli = get-esxcli -VMHost $esx -v2
        $setting = $esxcli.system.module.parameters.list.Invoke(@{module="iscsi_vmk"}) | Where-Object {$_.Name -eq 'iscsivmk_LunQDepth'}
        
        if ($verbose -eq $true){ $setting | Format-List | Format-Color @{"Value\s*:\s(?!16)" = 'Red'; "Value\s*:\s*$DateraIscsiQueueDepth " = 'Green'}}
        if ($succinct -eq $true)
        {
            if ($setting.Value -eq $DateraIscsiQueueDepth )
            {    Write-Host -ForegroundColor Green "iSCSI dueue depth is $($setting.value)"}
            else
            {    Write-Host -ForegroundColor Red "Deviation: iSCSI dueue depth is $($setting.value)"}
        }
        $optimalQD = $true
        if ($setting.Value -eq "")
        {
            $results.Item($index).Found_Queue_Depth = "NotConfigured"
            $optimalQD = $false
        }
        else
        {
            $results.Item($index).Found_Queue_Depth = $Setting.Value
            if ($setting.Value -ne $DateraIscsiQueueDepth ){
                $optimalQD = $false}
        }
        if (-not $optimalQD -and $safeHosts.Contains($esx))
        {
            $DQDString = "iscsiVMK_LunQDepth=$DateraIscsiQueueDepth"
            if ($verbose -or $succinct){Write-Host "Identified this as a safe host to fix automatically, Attempting fix."}
            $qDepth = @{
                    module = 'iscsi_vmk'
                    parameterstring = 'iscsiVMK_LunQDepth='+$DateraIscsiQueueDepth
                    }
            try { 
                $setChange = $esxcli.system.module.parameters.set.Invoke($qDepth)
                Write-Host "Fix successful." -ForegroundColor Green
                $results.Item($index).Found_Queue_Depth = $setChange.Value
            }
            catch
            {Write-Host "Fix Failed." -foregroundColor Red }

        }
        if ($results.Item($index).Found_Queue_Depth -ne $DateraIscsiQueueDepth  -and $results.Item($index).Opt_Status -eq "Optimal") {$results.Item($index).Opt_Status = "Suboptimal"}



########
########    Item 3: Delayed Ack
########
##
##  Turn Off DelayedAck for Random Workloads
##  Default application value is 1 (Enabled)
##  Modified application value is 0 (Disabled)
##
##  Alternate method of implementation:
##      export iscsi_if=`esxcli iscsi adapter list | grep iscsi_vmk | awk '{ print $1 }'`
##      vmkiscsi-tool $iscsi_if -W -a delayed_ack=0
##
##      export iscsi_if=`esxcli iscsi adapter list | grep iscsi_vmk | awk '{ print $1 }'`
##      vmkiscsi-tool -W $iscsi_if | grep delayed_ack                 
##      or
##      vmkiscsid --dump-db | grep Delayed
##  For details, please refer to https://kb.vmware.com/s/article/1002598
##
########

        if ($verbose -eq $true){Write-Output ("==== Delayed ACK of software iSCSI adapter on " + $esx.Name + " ====")}
        $adapterId = $esx.ExtensionData.config.StorageDevice.HostBusAdapter | Where{$_.Driver -match "iscsi_vmk"}        
        if ($adapterId.Count -gt 1)
        { 
            Write-Host -ForegroundColor DarkRed -BackgroundColor Yellow "Warning: Multiple iSCSI Adapters Found, results may be inaccurate"
            if ($results.Item($index).Opt_Status -eq "Optimal")
                {$results.Item($index).Opt_Status = "Unclear"}
        }
        foreach($adapter in $adapterId){
            $adapter_name = $adapter.IScsiName
            $setting =  $esxcli.iscsi.adapter.param.get.Invoke(@{adapter=$adapter.Device}) | Where{$_.Name -eq "DelayedACK"} 
            
            if ($verbose) 
            {
                Write-Object $setting | Format-List | Format-Color @{"Current\s*:\s*true" = 'Red'; "Current\s*:\s*false" = 'Green'}
            }
            elseif ($succinct){
                if ($setting.Current -eq "false"){Write-Host "Delayed Ack is off." -ForegroundColor Green}
                else{Write-Host "Deviation: Delayed Ack is on." -ForegroundColor Red}
            }
            $results.Item($index).Found_Delayed_Ack = $setting.Current
            if ($setting.Current -eq "true")
            {
                if($safehosts.Contains($esx)){
                    if ($verbose -or $succinct){Write-Host "Identified this as a safe host to fix automatically, Attempting fix."}
                    try {
                        $options = New-Object VMWare.Vim.HostInternetScsiHbaParamValue[] (1)
                        $options[0] = New-Object VMware.Vim.HostInternetScsiHbaParamValue
                        $options[0].key = "DelayedAck"
                        $options[0].value = $true

                        $HostiSCSISoftwareAdapterHBAID = $adapter.device
                        $HostStorageSystem = Get-View -ID $HostStorageSystemID
                        $HostStorageSystem.UpdateInternetScsiAdvancedOptions($HostiSCSISoftwareAdapterHBAID, $null, $options)


                        Write-Host "Fix successful." -ForegroundColor Green
                        $results.Item($index).Found_Delayed_Ack = "false"
                    }
                    catch
                    {Write-Host "Fix Failed." -foregroundColor Red }
                }
            }
            if ($results.Item($index).Found_Delayed_Ack -eq "true" -and $results.Item($index).Opt_Status -eq "Optimal")
                {$results.Item($index).Opt_Status = "Suboptimal"}
        }

        if ($adapterId.Count -eq 0)
        {
            if ($verbose -eq $true -or $succinct -eq $true){
                Write-Host -ForegroundColor Red "Deviation: No iSCSI Adapter Found."
            }
            $results.Item($index).Found_Delayed_Ack = "NoAdapter"
        }



########
########    Item 4: NMP SATP Rule
########
##
##  Create Custom SATP Rule for DATERA
##  
##  Alternate method of implementation:
##  esxcli storage nmp satp rule add -s VMW_SATP_ALUA -P VMW_PSP_RR -O iops=1 -V DATERA -e "DATERA custom SATP rule"
##  add(boolean boot, 
##      string claimoption, 
##      string description, 
##      string device, 
##      string driver, 
##      boolean force, 
##      string model, 
##      string option, 
##      string psp, 
##      string pspoption, 
##      string satp, 
##      string transport, 
##      string type, 
##      string vendor)
##      -s = The SATP for which a new rule will be added
##      -P = Set the default PSP for the SATP claim rule
##      -O = Set the PSP options for the SATP claim rule (option=string
##      -V = Set the vendor string when adding SATP claim rules. Vendor rules are mutually exclusive with driver rules (vendor=string)
##      -e = Claim rule description
##  
##  !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
##  !!! Configuration changes take effect after rebooting ESXI hosts            !!!
##  !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
##  
##  To remove the claim rule:
##  esxcli storage nmp satp rule remove -s VMW_SATP_ALUA -P VMW_PSP_RR -O iops=1 -V DATERA -e "DATERA custom SATP rule"
##  To verify the claim rule:
##  esxcli storage nmp satp rule list
##  
## Result Looks like
##  ClaimOptions :
##  DefaultPSP   : VMW_PSP_RR
##  Description  : DATERA custom SATP rule
##  Device       :
##  Driver       :
##  Model        : 
##  Name         : VMW_SATP_ALUA
##  Options      :
##  PSPOptions   : iops='1'
##  RuleGroup    : user
##  Transport    :
##  Vendor       : DATERA
## 
########

        if ($verbose -eq $true) {Write-Output ("==== NMP SATP RULE of DATERA on " + $esx.Name + " ====")}
        $NmpSatpRule = $esxcli.storage.nmp.satp.rule.list.Invoke() | Where{$_.Vendor -eq "DATERA"}
        if ($NmpSatpRule -eq $null) {
            if ($verbose -or $succinct){ Write-Host -ForegroundColor Red "Deviation: No customized NMP SATP RULE for DATERA on $($esx.Name)"}
            $results.Item($index).Found_NMP_SATP_Rule = 'Not Present'
            if ($safeHosts.Contains($esx))
            {
                if ($verbose -or $succinct){Write-Host "Identified this as a safe host to fix automatically, Attempting fix."}
                $SatpArgs = $esxcli.storage.nmp.satp.rule.remove.createArgs()
                $SatpArgs.description = "DATERA custom SATP Rule"
                $SatpArgs.vendor = "DATERA"
                $SatpArgs.satp = "VMW_SATP_ALUA"
                $SatpArgs.psp = "VMW_PSP_RR"
                $SatpArgs.pspoption = "iops=1"
                $result=$esxcli.storage.nmp.satp.rule.add.invoke($SatpArgs)
                 
                if ($result){ 
                        if ($verbose -or $succinct){Write-Host "DATERA custom SATP rule [RR, iops=1] is created for $($esx.name)" -ForegroundColor Green}
                        $results.Item($index).Found_NMP_SATP_Rule = 'Present'
                     
                if ($verbose){
                         Write-Host "
                     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
                     !!                                                                !!
                     !!  Configuration changes take effect after rebooting ESXI hosts  !!
                     !!  Please move ESXi host to maintenance mode, then reboot them   !!
                     !!                                                                !!
                     !!  Please DON'T reboot ESXi if there are datastores/storage      !!
                     !!  connected to ESXi host                                        !!
                     !!                                                                !!
                     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
                             " -ForegroundColor Magenta
                     }
                if ($succinct){Write-Host "!!!!!! Configuration changes take effect after rebooting ESXI hosts !!!!!!" -ForegroundColor Cyan}
                }
                else
                {
                   $results.Item($index).Found_NMP_SATP_Rule = 'NotPresent'
                    if ($results.Item($index).Opt_Status -eq "Optimal"){$results.Item($index).Opt_Status = "Suboptimal"}
                }
            }
            else
            {
               $results.Item($index).Found_NMP_SATP_Rule = 'NotPresent'
               if ($results.Item($index).Opt_Status -eq "Optimal"){$results.Item($index).Opt_Status = "Suboptimal"}
            }
        }
        else
        {
            if ($verbose) {Write-Output ($NmpSatpRule) | Format-Color @{'' = 'Green'}}
            if ($succinct) {Write-Host -ForegroundColor Green "Found expected NMP SATP Rule."}
            $results.Item($index).Found_NMP_SATP_Rule = 'Present'
        }



########
########    Cleanup    
########        

    if ($verbose -or $succinct)
    {
        if($results.Item($index).Opt_Status -ne "Optimal")
        {
            if($results.Item($index).Connection_State -eq "Maintenance")
            {            
                Write-Host "Host is in Maintenance Mode, Run script with update parmeter to fix." -ForegroundColor Green
            }
            elseif ($results.Item($index).Found_ATS_HB -eq 0)
            {
                Write-Host "Please consider fixing this host for performance improvements." -ForegroundColor Yellow
            }
            else 
            {
                Write-Host "This host is a danger to your environment.  Fix immediately!" -ForegroundColor Red
            }
        }
        Write-Host ""
    }
}

}

########
########     Output
########

if ($verbose -or $succinct){
Write-PSObject $results -MatchMethod Exact, Exact, Exact, Query, Query, Query, `
                                     Exact, Exact, Query, Query, Exact, Exact, Query, Exact `
                        -Column "Opt_Status", "Connection_State", "Found_ATS_HB", "Found_Queue_Depth", "Found_Delayed_Ack", "Found_NMP_SATP_Rule", `
                                    "Found_ATS_HB", "Found_Queue_Depth", "Found_Delayed_Ack", "Name", "Opt_Status" , "Opt_Status", "Name", "Reboot_Required" `
                        -Value "Critical", "Maintenance", "1", "'Found_Queucre_Depth' -ne '16'", "'Found_Delayed_Ack' -ne 'false'", "'Found_NMP_SATP_Rule' -ne 'Present'", `
                                    "0", 16, "'Found_Delayed_Ack' -eq 'false'", "'Opt_Status' -eq 'Critical' -and 'Connection_State' -ne 'Maintenance'", `
                                    "Suboptimal", "Optimal", "'Opt_Status' -eq 'Suboptimal' -and 'Connection_State' -ne 'Maintenance'", "Yes"  `
                        -ValueForeColor Red, Green, Red, Red, Red, Red, `
                                    Green, Green, Green, Red, Yellow, Green, Yellow, Cyan, White 
                        
}

$critical = 0;
$suboptimal = 0;  
$maintmode = 0;
$rebootNeeded = 0;

foreach ($esxiHost in $results)
{
    if ($esxiHost.Opt_Status -eq "Critical"){
        $critical++
        if ($esxiHost.Connection_State -eq "Maintenance")
        {
            $maintmode ++
        }
    }
    if ($esxiHost.Opt_Status -eq "Suboptimal"){
        $suboptimal++
    }
    if ($esxiHost.Reboot_Required -eq "Yes"){
        $rebootNeeded ++
    }
}
if ($critical -gt 0 -or $suboptimal -gt 0 -or $rebootNeeded -gt 0)
{
    Write-Host "
    Found $critical Critical, $maintmode MM Critical, and $suboptimal Suboptimal hosts in $vcenterServer"
    Write-Host "$rebootNeeded Hosts need to be rebooted."
    $Header = @"
<style>
TABLE {  font-family: Tahoma, Geneva, sans-serif;
    border: 1.5px solid #bbFFFF;
    text-align: center;
    font-size: 11px;
    border-collapse: collapse;}
TD {border-width: 2px; padding: 3px 15px; border-style: solid; border-color: blue;}
H2 {font-family: Tahoma, Geneva, sans-serif;}
H3 {font-family: Tahoma, Geneva, sans-serif;}
</style>
"@

    $body =  $results | ConvertTo-Html -Body "<h2>Found $critical Critical, $maintmode MM Critical, and $suboptimal Suboptimal hosts in $vcenterServer </h2>" -Head $header -PostContent "<h3>Better living through automation.(tm)</h3>Report run at $((get-date).ToUniversalTime().ToString("yyyy-MM-dd HH:mm:ss UTC"))" | Out-String

    if ($SendEmail)
    {
        if ($critical -gt 0 )
        {$subject = "[CRITICAL] Datera Config Checker: $vcenterServer"
        }
        else
        {$subject = "[info] Datera Config Checker: $vcenterServer"}
        Email-Alert -To "$SMTP_TO" -Subject $subject -Message $body -SMTP_RELAY $SMTP_RELAY -SMTP_FROM $SMTP_FROM
    }
}
else{
Write-Host "Great Job, everything looks good."}



