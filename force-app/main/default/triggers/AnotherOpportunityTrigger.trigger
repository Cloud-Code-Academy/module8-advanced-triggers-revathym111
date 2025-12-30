/*
AnotherOpportunityTrigger Overview

This trigger was initially created for handling various events on the Opportunity object. It was developed by a prior developer and has since been noted to cause some issues in our org.

IMPORTANT:
- This trigger does not adhere to Salesforce best practices.
- It is essential to review, understand, and refactor this trigger to ensure maintainability, performance, and prevent any inadvertent issues.

ISSUES:
Avoid nested for loop - 1 instance
Avoid DML inside for loop - 1 instance
Bulkify Your Code - 1 instance
Avoid SOQL Query inside for loop - 2 instances
Stop recursion - 1 instance

RESOURCES: 
https://www.salesforceben.com/12-salesforce-apex-best-practices/
https://developer.salesforce.com/blogs/developer-relations/2015/01/apex-best-practices-15-apex-commandments
*/
trigger AnotherOpportunityTrigger on Opportunity (before insert, after insert, before update, after update, before delete, after delete, after undelete) {
    if (Trigger.isBefore){
        if (Trigger.isInsert){
            // Set default Type for new Opportunities
            /*Opportunity opp = Trigger.new[0];
            if (opp.Type == null){
                opp.Type = 'New Customer';
            } */
            for(Opportunity opp : Trigger.new){ //Bulkify the Code - 1 instance
                if(opp.Type == null){
                    opp.Type = 'New Customer';
                }
            }       
        } else if (Trigger.isDelete){
            // Prevent deletion of closed Opportunities
            for (Opportunity oldOpp : Trigger.old){
                if (oldOpp.IsClosed){
                    oldOpp.addError('Cannot delete closed opportunity');
                }
            }
        }
    }

    if (Trigger.isAfter){
        if (Trigger.isInsert){
            // Create a new Task for newly inserted Opportunities
            List<Task> taskList = new List<Task> ();
            for (Opportunity opp : Trigger.new){
                Task tsk = new Task();
                tsk.Subject = 'Call Primary Contact';
                tsk.WhatId = opp.Id;
                tsk.WhoId = opp.Primary_Contact__c;
                tsk.OwnerId = opp.OwnerId;
                tsk.ActivityDate = Date.today().addDays(3);
                taskList.add(tsk);
                //insert tsk; Avoid DML inside for loop - 1 instance
            }
            insert taskList;
        } else if (Trigger.isUpdate){
            // Append Stage changes in Opportunity Description
            //Stop recursion - 1 instance
            Boolean stopTrigger = Trigger_Setting__mdt.getInstance('AnotherOpportunityTrigger')?.Disable_Trigger__c;
            Boolean stopTriggerHelper = OpportunityTriggerHelper.hasRun;
            if(stopTrigger == false && stopTriggerHelper == false){
                OpportunityTriggerHelper.hasRun = true;
                for (Opportunity opp : Trigger.new){ //Avoid nested for loop - 1 instance
                    Opportunity oppOld = Trigger.oldMap.get(opp.Id); //Replace nested for loop with trigger.oldMap
                    //for (Opportunity oldOpp : Trigger.old){
                        if (opp.StageName != null && opp.StageName != oppOld.StageName && opp.Id == oppOld.Id){
                            opp.Description += '\n Stage Change:' + opp.StageName + ':' + DateTime.now().format();
                        }
                    //}                
                }
            }
            update Trigger.new;
        }
        // Send email notifications when an Opportunity is deleted 
        else if (Trigger.isDelete){
            notifyOwnersOpportunityDeleted(Trigger.old);
        } 
        // Assign the primary contact to undeleted Opportunities
        else if (Trigger.isUndelete){
            assignPrimaryContact(Trigger.newMap);
        }
    }

    /*
    notifyOwnersOpportunityDeleted:
    - Sends an email notification to the owner of the Opportunity when it gets deleted.
    - Uses Salesforce's Messaging.SingleEmailMessage to send the email.
    */
    private static void notifyOwnersOpportunityDeleted(List<Opportunity> opps) {
        List<Messaging.SingleEmailMessage> mails = new List<Messaging.SingleEmailMessage>();

        Set<Id> ownerIds = new Set<Id> ();
        for(Opportunity opp : opps){
            ownerIds.add(opp.OwnerId);
        }

        //List<User> usersList = [SELECT Id, Email FROM User WHERE Id IN :ownerIds];
        Map<Id, User> usersMap = new Map<Id, User> ([SELECT Id, Email FROM User WHERE Id IN :ownerIds]);
        for (Opportunity opp : opps){
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage(); //Avoid SOQL Query inside for loop - 2 instances
            //String[] toAddresses = new String[] {[SELECT Id, Email FROM User WHERE Id = :opp.OwnerId].Email};
            String [] toAddresses = new String[] {usersMap.get(opp.OwnerId).Email}; // usersMap.get(opp.OwnerId).Email is an element of array, add method not in array
            mail.setToAddresses(toAddresses);
            mail.setSubject('Opportunity Deleted : ' + opp.Name);
            mail.setPlainTextBody('Your Opportunity: ' + opp.Name +' has been deleted.');
            mails.add(mail);
        }        
        
        try {
            Messaging.sendEmail(mails);
        } catch (Exception e){
            System.debug('Exception: ' + e.getMessage());
        }
    }

    /*
    assignPrimaryContact:
    - Assigns a primary contact with the title of 'VP Sales' to undeleted Opportunities.
    - Only updates the Opportunities that don't already have a primary contact.
    */
    private static void assignPrimaryContact(Map<Id,Opportunity> oppNewMap) {        
        Map<Id, Opportunity> oppMap = new Map<Id, Opportunity>();
        //Collected AccountIds from the oppNewMap
        Set<Id> accountIds = new Set<Id> ();
        for(Opportunity opp : oppNewMap.values()){
            if(opp.AccountId != null){
                accountIds.add(opp.AccountId);
            }
        }
        //Contact[] primaryContacts = [SELECT Id, AccountId FROM Contact WHERE Title = 'VP Sales' AND AccountId IN :accountIds];
        //Queried Contacts with the given condition and AccountId in set accountIds
        Map<Id, Contact> primaryContacts = new Map<Id, Contact> ([SELECT Id, AccountId FROM Contact WHERE Title = 'VP Sales' AND AccountId IN :accountIds]);

        Map<Id, Contact> primaryContactsByAccount = new Map<Id, Contact> ();
        //Collect contact with that Account id and store AccountId, Contact in the Map
        for(Contact con: primaryContacts.values()){
            if(!primaryContactsByAccount.containsKey(con.AccountId)){
                primaryContactsByAccount.put(con.AccountId, con);
            }
        }
        for (Opportunity opp : oppNewMap.values()){ //Avoid SOQL Query inside for loop - 2 instances            
            //Contact primaryContact = [SELECT Id, AccountId FROM Contact WHERE Title = 'VP Sales' AND AccountId = :opp.AccountId LIMIT 1];
            if (opp.Primary_Contact__c == null && primaryContactsByAccount.containsKey(opp.AccountId)){
                Opportunity oppToUpdate = new Opportunity(Id = opp.Id);
                oppToUpdate.Primary_Contact__c = primaryContactsByAccount.get(opp.AccountId).Id;
                oppMap.put(opp.Id, oppToUpdate);
                }
            }
        update oppMap.values();
    }
}