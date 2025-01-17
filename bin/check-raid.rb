#! /usr/bin/env ruby
# frozen_string_literal: true

#
#   check-raid
#
# DESCRIPTION:
#   Generic raid check
#   Supports HP, Adaptec, and MegaRAID controllers. Also supports software RAID.
#
# OUTPUT:
#   plain text
#
# PLATFORMS:
#   Linux
#
# DEPENDENCIES:
#   gem: sensu-plugin
#
# USAGE:
#   Use `--sudo true` option if the binaries require root permissions.
#
#   Create a file named /etc/sudoers.d/sensu-check-raid
#     and list all allowed commands with the correct path and options:
#   Example:
#     sensu ALL=(ALL) NOPASSWD: /usr/sbin/megacli -AdpAllInfo -aALL -NoLog
#
# NOTES:
#
# LICENSE:
# Originally by Shane Feek, modified by Alan Smith. Date: 07/14/2014#
# Released under the same terms as Sensu (the MIT license); see LICENSE  for details.
#

require 'sensu-plugin/check/cli'

#
# Check Raid
#
class CheckRaid < Sensu::Plugin::Check::CLI
  option :log,
         description: 'Enables or disables logging for megacli',
         short: '-l VALUE',
         long: '--log VALUE',
         boolean: true,
         default: false

  option :sudo,
         description: 'Uses sudo to run commands',
         short: '-s VALUE',
         long: '--sudo VALUE',
         boolean: true,
         default: false

  option :megacli,
         description: 'the MegaCli executable',
         short: '-m CMD',
         long: '--megacli CMD',
         default: '/usr/sbin/megacli'

  # Check software raid
  #
  def check_software_raid
    return unless File.exist?('/proc/mdstat')
    contents = File.read('/proc/mdstat')
    mg = contents.lines.grep(/active|blocks/)
    return if mg.empty?
    sg = mg.to_s.lines.grep(/\]\(F\)|[\[U]_/)
    if sg.empty?
      ok 'Software RAID OK'
    else
      warning 'Software RAID warning'
    end
  end

  # Check HP raid
  #
  def check_hp
    return unless File.exist?('/usr/bin/cciss_vol_status')
    contents = `#{@cmd_prefix}/usr/bin/cciss_vol_status /dev/sg0`
    c = contents.lines.grep(/status\: OK\./)
    # #YELLOW
    if c.empty?
      warning 'HP RAID warning'
    else
      ok 'HP RAID OK'
    end
  end

  # Check Adaptec raid controllers
  #
  def check_adaptec
    return unless File.exist?('/usr/StorMan/arcconf')
    contents = `#{@cmd_prefix}/usr/StorMan/arcconf GETCONFIG 1 AL`

    mg = contents.lines.grep(/Controller Status/)
    # #YELLOW
    if mg.empty?
      warning 'Adaptec Physical RAID Controller Status Read Failure'
    else
      sg = mg.to_s.lines.grep(/Optimal/)
      warning 'Adaptec Physical RAID Controller Failure' if sg.empty?
    end

    mg = contents.lines.grep(/Status of logical device/)
    # #YELLOW
    if mg.empty?
      warning 'Adaptec Logical RAID Controller Status Read Failure'
    else
      sg = mg.to_s.lines.grep(/Optimal/)
      warning 'Adaptec Logical RAID Controller Failure' if sg.empty?
    end

    mg = contents.lines.grep(/S\.M\.A\.R\.T\.   /)
    # #YELLOW
    if mg.empty?
      warning 'Adaptec S.M.A.R.T. Status Read Failure'
    else
      sg = mg.to_s.lines.grep(/No/)
      warning 'Adaptec S.M.A.R.T. Disk Failed' if sg.empty?
    end

    ok 'Adaptec RAID OK'
  end

  # Check Megaraid
  #
  def check_mega_raid
    return unless File.exist?(config[:megacli])
    contents = if config[:log]
                 `#{@cmd_prefix}#{config[:megacli]} -AdpAllInfo -aALL`
               else
                 `#{@cmd_prefix}#{config[:megacli]} -AdpAllInfo -aALL -NoLog`
               end
    failed = contents.lines.grep(/(Critical|Failed) Disks\s+\: 0/)
    degraded = contents.lines.grep(/Degraded\s+\: 0/)
    # #YELLOW
    if failed.empty? || degraded.empty?
      warning 'MegaRaid RAID warning'
    else
      ok 'MegaRaid RAID OK'
    end
  end

  # Main function
  #
  def run
    @cmd_prefix = config[:sudo] ? 'sudo ' : ''
    check_software_raid
    unless `lspci`.lines.grep(/RAID/).empty?
      check_hp
      check_adaptec
      check_mega_raid

      unknown 'Missing software for RAID controller'
    end

    ok 'No RAID present'
  end
end
