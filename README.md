# Avarice Guild Bank
## Overview
Avarice Guild Bank provides an extension to the built in guild bank money log to enable a more comprehensive analysis of incoming and outgoing expenses over time, along with supporting an efficient means of providing EP rewards for donations by guild members.

Avarice Guild Bank will only track transactions conducted by those who have the addon, and will promulgate its complete database between all users of the addon within the guild.

Please note that transaction data will only be held up to a maximum of three months from the date of the transaction. All data older than this will be purged from the database on load.

## Synchronisation
Avarice Guild Bank maintains a local table of all transactions conducted and synchronises this database both automatically and manually as triggered by the user.

Data will be automatically broadcast to all online guild members after the following events:
- Upon logging into the game.
- After closing the Blizzard Guild Bank window.
- After closing the Avarice Guild Bank window (this window).

Data may also be manually synchronised by clicking the `[Sync]` button on the `[Log]` tab. Doing this will request all online guild members to send you their database.

Please note that the manual synchronisation option may take a short amount of time to complete, depending on how many guild members are online at the time.

## Transaction Log
On the `[Log]` tab, the lower half of the frame consists of the Transaction Log. Here you will be able to see all transactions that match the current filter settings, and can select transactions to apply actions to.

Deposits are shown in green text, while withdrawals are shown in red text surrounded by parentheses.

Select transactions to apply actions to by ticking the checkbox to the left of the desired transaction. Multiple transactions may be selected and actioned in a single step. Please note that only actions with a status of “Pending” may be selected.

You can select/deselect all transactions by using the checkbox in the header row.

Change pages by using the `[<<][<][>][>>]` controls located at the top of the transaction log.

## Filtering and Sorting
### Filtering
The Transaction Log can be filtered based on the date and status of the transaction. Simply use the dropdowns to select the desired options and the transactions displayed will update to match.

Please note that if using custom date filtering, then custom dates must be entered in the format `dd/mm/yyyy`. Attempting to enter a date in any other format will be denied.

### Sorting
The Transaction Log can be sorted by clicking on any of the header labels (e.g. Status). Click the same label multiple times to change the order of the sort.

## Actions
The Action buttons allow you to apply particular actions to transactions in the log. Please note that all actions are final, and only one action may be taken for any given transaction. That is, if you ignore a transaction then this transaction will be ignored for all other guild members. Likewise if you award EP to a transaction, this transaction will be marked as having been awarded EP for all other guild members.

Actions will be applied to all currently selected transactions in the log.

Actions are only able to be performed by those with suitable permissions in the guild (i.e. officers). For those players with insufficient privileges these buttons will be disabled.

### Award EP
Awards the amount of EP as specified in `[Settings]` to the player who made each selected transaction.

Please note that this will award the EP amount once per transaction selected. That is, if multiple transactions made by the same player are selected then EP will be awarded multiple times to this player, once for each selected transaction belonging to that player.

This action will only be available if you can see officer notes and have the EPGP-Classic addon installed.

### Ignore
Marks the transaction as ignored.

This is useful to allow you to acknowledge a given transaction as having been assessed and not relevant for the purposes of awarding EP (for example, depositing the proceeds from selling guild bank items).

The main purpose of the Ignore function is to allow filtering of transactions by “Pending” to see only new transactions that have been made since EP was last awarded.

It is heavily recommended to ignore any superfluous transactions and filter them out to improve performance of the Avarice Guild Bank frame.