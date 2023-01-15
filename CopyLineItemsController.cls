/*
    Version 10.9.0
    Copyright (c) Kinetic Growth 2022
    info@kineticgrowth.com

    This file is provided as a part of the kinetic-growth application and may
    not be copied and/or distributed without the express written permission of
    Kinetic Growth.
 */

public without sharing class CopyLineItemsController {

  final static String MAPPINGS_FILENAME = 'CopyLineItems Mappings';
  final static String SETTINGS_FILENAME = 'CopyLineItems Settings';
  final static String PUBLIC_GROUP_DEVELOPER_NAME = 'CopyLineItems_Sharing_Group';
  final static String WORKSPACE_DEVELOPER_NAME = 'CopyLineItems_Workspace';  

  final public static Boolean featureCopyClipboardLineItems = Permissions.checkPermission(ApplicationPermissionSet__c.Feature_CopyClipboardLineItems__c, null).getIsSuccess();

  final public static Boolean featureOpportunityQuoteSync = Permissions.checkPermission(ApplicationPermissionSet__c.Feature_OpportunityQuoteSync__c, null).getIsSuccess();

  public final static Integer NOTHING_CHANGED = 0;
  public final static Integer CUSTOM_FIELDS_CHANGED = 1;
  public final static Integer STANDARD_FIELDS_CHANGED = 2;
  public final static Integer BOTH_FIELD_TYPES_CHANGED = 3;
  
  private static Map<String, Set<String>> sObjectFieldMap = new Map<String, Set<String>>();

  public static Map<Id, SObject> opptyLineItemsToQuoteLineItemsMap {
    get {
      if(opptyLineItemsToQuoteLineItemsMap == null){
        opptyLineItemsToQuoteLineItemsMap = new Map<Id, SObject>();
      }
      return opptyLineItemsToQuoteLineItemsMap;
    }
    private set;
  }

  public static Map<Id, Opportunity> opportunityMap {
    get {
      if(opportunityMap == null){
        opportunityMap = new Map<Id, Opportunity>();
      }
      return opportunityMap;
    }
    private set;
  }

  public static Map<Id, OpportunityLineItem> opportunityLineItemMap {
    get {
      if(opportunityLineItemMap == null){
        opportunityLineItemMap = new Map<Id, OpportunityLineItem>();
      }
      return opportunityLineItemMap;
    }
    private set;
  }

  /**
   *  Compares the fields of two list of sobjects of the same type
   *  @param soList1      First sobject list
   *  @param soList2      2nd sobject list
   *  @return Integer  Return the type of change: NOTHING_CHANGED, CUSTOM_FIELDS_CHANGED, STANDARD_FIELDS_CHANGED, BOTH_FIELD_TYPES_CHANGED
   */
  public static Integer compareSObjects(SObject[] soList1, SObject[] soList2){

    if(soList1 == null || soList2 == null || soList1.size() != soList2.size() || soList1.size() < 1){
      return NOTHING_CHANGED;
    }    
    String soType = String.valueOf(soList1[0].getSObjectType());
    Set<String> fieldSet = sObjectFieldMap.get(soType);
    if(fieldSet == null){
      fieldSet = new Set<String>();
      Set<String> unusedFields = new Set<String> { 'CreatedById', 'IsDeleted', 'LastActivityDate', 'LastModifiedById', 'LastModifiedDate', 'LastReferencedDate', 'SystemModstamp', 'LastViewedDate' };
      Map<String, Object> fieldObjectMap = soList1[0].getPopulatedFieldsAsMap();        
      for(String key : fieldObjectMap.keySet()){
        if(!unusedFields.contains(key)){
          fieldSet.add(key);
        }  
      }
      sObjectFieldMap.put(soType, fieldSet);
    }
    Integer[] resultList = new Integer[0];
    Boolean standardFieldChanged = false;
    Boolean customFieldChanged = false;

    for(Integer i = 0; i < soList1.size(); i++){
      for(String key : fieldSet){        
        if(String.valueOf(soList1[i].get(key)) != String.valueOf(soList2[i].get(key))){
          if(key.right(3) == '__c'){      
            customFieldChanged = true;
          }
          else {
            standardFieldChanged = true;
          }
        }
      }      
      if(standardFieldChanged && customFieldChanged){
        break;
      }
    }  
    if(standardFieldChanged && !customFieldChanged){
      return STANDARD_FIELDS_CHANGED;
    }
    else if(!standardFieldChanged && customFieldChanged){
      return CUSTOM_FIELDS_CHANGED;
    }
    else if(standardFieldChanged && customFieldChanged){
      return BOTH_FIELD_TYPES_CHANGED;
    }     
    return NOTHING_CHANGED;  
  } 

  /**
   *  Queries quote line item ids and quote ids associated with the opportunity line items into a map
   *
   *  @param opportunityLineItemIds  The ids of the opportunity line items.
   *  @param opportunityLineItems    The opportunity line items.
   */
  public static void initQuoteLineItems(Set<Id> opportunityLineItemIds, OpportunityLineItem[] opportunityLineItems){
    Set<Id> idSet = new Set<Id>();
    String[] fieldsQli = new String[] { 'Id', 'OpportunityLineItemId' };

    if(opportunityLineItemIds != null){
      idSet.addAll(opportunityLineItemIds);
    }
    if(opportunityLineItems != null){
      for(OpportunityLineItem oli : opportunityLineItems){
        idSet.add(oli.Id);
      }
    }
    if(idSet.size() > 0){
      for(Integer i = 1; i < opportunityQuoteLineItemMatchingFields.size(); i += 2){
        fieldsQli.add(opportunityQuoteLineItemMatchingFields[i]);
      }
      SObject[] qlis = Database.query('SELECT ' + String.join(fieldsQli, ',') + ', Quote.Id, Quote.OpportunityId, Quote.Opportunity.SyncedQuoteId FROM QuoteLineItem WHERE OpportunityLineItemId IN :idSet');
      for(SObject qli : qlis){
        if((Id)qli.getSObject('Quote').get('Id') == (Id)qli.getSObject('Quote').getSObject('Opportunity').get('SyncedQuoteId')){
          opptyLineItemsToQuoteLineItemsMap.put((Id)qli.get('OpportunityLineItemId'), qli);
        }
      }
    }
    else {
      opptyLineItemsToQuoteLineItemsMap = null;
    }
  }

  /**
   *  Queries opportunities and opportunity line items assocated with the quotes or quote line items
   *
   *  @param quotes                The quotes
   *  @param quoteLineItems        The quote line items
   *  @param onlyQueryIfNotExist   True if skip records that are already cached
   */
  public static void initQuoteToOpportunities(SObject[] quotes, SObject[] quoteLineItems, Boolean onlyQueryIfNotExist){

    String queryStrMaster;
    String queryStrDetail;
    Set<Id> opptyIds = new Set<Id>();
    Set<Id> oliIds = new Set<Id>();

    if(quotes != null && quotes.size() > 0){
      String[] fieldsOppty = new String[] { 'Id' };
      String[] fieldsOli = new String[] { 'Id', 'OpportunityId' };      
      for(SObject quote : quotes){
        if(onlyQueryIfNotExist && opportunityMap.containsKey((Id)quote.get('OpportunityId'))){
          continue;
        }
        opptyIds.add((Id)quote.get('OpportunityId'));
      }
      opptyIds.remove(null);
      if(opptyIds.size() < 1){
        return;
      }
      for(Integer i = 0; i < opportunityQuoteMatchingFields.size(); i += 2){
        fieldsOppty.add(opportunityQuoteMatchingFields[i]);
      }
      for(Integer i = 0; i < opportunityQuoteLineItemMatchingFields.size(); i += 2){
        fieldsOli.add(opportunityQuoteLineItemMatchingFields[i]);
      }
      Set<String> fieldsOliSet = new Set<String>(fieldsOli);
      fieldsOli = new List<String>(fieldsOliSet);
      Set<String> fieldsOpptySet = new Set<String>(fieldsOppty);
      fieldsOppty = new List<String>(fieldsOpptySet);      
      
      queryStrMaster = 'SELECT ' + String.join(fieldsOppty, ', ') + ' FROM Opportunity WHERE Id IN :opptyIds';
      queryStrDetail = 'SELECT ' + String.join(fieldsOli, ', ') + ' FROM OpportunityLineItem WHERE OpportunityId IN :opptyIds';
      opportunityMap = new Map<Id, Opportunity>((List<Opportunity>)Database.query(queryStrMaster));
      opportunityLineItemMap = new Map<Id, OpportunityLineItem>((List<OpportunityLineItem>)Database.query(queryStrDetail));
    }
    else if(quoteLineItems != null && quoteLineItems.size() > 0){
      String[] fieldsOppty = new String[] { 'Id' };
      String[] fieldsOli = new String[] { 'Id', 'OpportunityId' };

      for(SObject qli : quoteLineItems){
        if(onlyQueryIfNotExist && opportunityLineItemMap.containsKey((Id)qli.get('OpportunityLineItemId'))){
          continue;
        }
        oliIds.add((Id)qli.get('OpportunityLineItemId'));
      }
      oliIds.remove(null);
      if(oliIds.size() < 1){
        return;
      }
      for(Integer i = 0; i < opportunityQuoteMatchingFields.size(); i += 2){
        fieldsOppty.add(opportunityQuoteMatchingFields[i]);
      }
      for(Integer i = 0; i < opportunityQuoteLineItemMatchingFields.size(); i += 2){
        fieldsOli.add(opportunityQuoteLineItemMatchingFields[i]);
      }
      Set<String> fieldsOliSet = new Set<String>(fieldsOli);
      fieldsOli = new List<String>(fieldsOliSet);
      Set<String> fieldsOpptySet = new Set<String>(fieldsOppty);
      fieldsOppty = new List<String>(fieldsOpptySet); 

      queryStrDetail = 'SELECT ' + String.join(fieldsOli, ', ') + ' FROM OpportunityLineItem WHERE Id IN :oliIds';
      opportunityLineItemMap = new Map<Id, OpportunityLineItem>();

      for(OpportunityLineItem oli : Database.query(queryStrDetail)){      
        opportunityLineItemMap.put(oli.Id, oli);
        opptyIds.add(oli.OpportunityId);
      }
      queryStrMaster = 'SELECT ' + String.join(fieldsOppty, ', ') + ' FROM Opportunity WHERE Id IN :opptyIds';
      opportunityMap = new Map<Id, Opportunity>((List<Opportunity>)Database.query(queryStrMaster));    
    }
    else {
      opportunityMap = null;
      opportunityLineItemMap = null;
    }
  }

  public static String orgNamespace {
    get {
      if(orgNamespace == null){
        orgNamespace = [SELECT NamespacePrefix FROM Organization].NamespacePrefix;
        orgNamespace = orgNamespace != null ? orgNamespace : '';
      }
      return orgNamespace;
    }
    set;
  }

  /**
   *   Wrapper class for SObject fields
   */
  public class FieldWrapper {

    @AuraEnabled
    public String fieldLabel;
    @AuraEnabled
    public String fieldName;
    @AuraEnabled
    public String fieldNameNoNS;
    @AuraEnabled
    public String namespace;
    @AuraEnabled
    public String fieldType;
    @AuraEnabled
    public Integer fieldLength;
    @AuraEnabled
    public Boolean isUnique;
    @AuraEnabled
    public Boolean isCaseSensitive;
    @AuraEnabled
    public String[] pickListValues;

    public FieldWrapper(String fieldName, String fieldLabel, String fieldType, Integer fieldLength){
      this.fieldName = fieldName;
      this.fieldlabel = fieldLabel;
      this.fieldType = fieldType;
      this.fieldLength = fieldLength;
    }

    public void setFieldNameNoNS(){
      if(fieldName.indexOf('__') > 0){
        String[] parts = fieldName.split('__');
        if(parts.size() == 3){
          namespace = parts[0];
          fieldNameNoNS = parts[1] + '__c';
        }
        else if(parts.size() == 2){
          namespace = '';
          fieldNameNoNS = parts[0] + '__c';
        }
      }
      else {
        namespace = '';
        fieldNameNoNS = fieldName;
      }
    }

    public void setPickListValues(List<Schema.PicklistEntry> picklistEntries){
      this.picklistValues = new String[0];
      for(Schema.PicklistEntry picklistEntry : picklistEntries){
        this.picklistValues.add(picklistEntry.getValue());
      }      
    }      
  }
  
  public final static String[] opportunityQuoteMatchingFields = retrieveMatchingCustomFields('Opportunity', 'Quote', true);
  public final static String[] opportunityQuoteLineItemMatchingFields = retrieveMatchingCustomFields('OpportunityLineItem', 'QuoteLineItem', true);

  public static String[] retrieveMatchingCustomFields(String sObjectName1, String sObjectName2, Boolean isIgnoreFieldType){
    FieldWrapper[] fieldWrappers1 = retrieveFields(sObjectName1, false, false);
    FieldWrapper[] fieldWrappers2 = retrieveFields(sObjectName2, false, false);
    Map<String, FieldWrapper> fieldMap1 = new Map<String, FieldWrapper>();
    Map<String, FieldWrapper> fieldMap2 = new Map<String, FieldWrapper>();

    for(FieldWrapper fw : fieldWrappers1){
      if(fw.fieldName.right(3) == '__c'){
        fw.setFieldNameNoNS();
        if(fw.namespace == orgNamespace || fw.namespace == 'KGRenewal' || fw.namespace == 'SaastepsQuote'){
          FieldWrapper existingFw = fieldMap1.get(fw.fieldNameNoNS);
          // ignore shadowed fields
          if(existingFw != null && existingFw.namespace == 'KGRenewal'){
            continue;
          }
          fieldMap1.put(fw.fieldNameNoNS, fw);
        }
      }
    }
    for(FieldWrapper fw : fieldWrappers2){
      if(fw.fieldName.right(3) == '__c'){
        fw.setFieldNameNoNS();
        if(fw.namespace == orgNamespace || fw.namespace == 'KGRenewal' || fw.namespace == 'SaastepsQuote'){
          FieldWrapper existingFw = fieldMap2.get(fw.fieldNameNoNS);
          // ignore shadowed fields
          if(existingFw != null && existingFw.namespace == 'KGRenewal'){
            continue;
          }
          fieldMap2.put(fw.fieldNameNoNS, fw);
        }
      }
    }
    String[] matchResults = new String[0];
    for(String fieldName : fieldMap1.keySet()){
      if(fieldMap2.containsKey(fieldName)){
        FieldWrapper fw1 = fieldMap1.get(fieldName);
        FieldWrapper fw2 = fieldMap2.get(fieldName);
        if(isIgnoreFieldType || fw1.fieldType == fw2.fieldType){
          matchResults.add(fw1.fieldName);
          matchResults.add(fw2.fieldName);
        }
      }
    }
    return matchResults;
  }

  /**
   *  retrieve fields for sobject
   *  @param sObjectName      Name of sobject
   *  @param isUpdateable     True to if fields must be updateable
   *  @return FieldWrapper[]  List of FieldWrapper objects
   */
  public static FieldWrapper[] retrieveFields(String sObjectName, Boolean isUpdateable) {
    return retrieveFields(sObjectName, isUpdateable, true);
  }

  /**
   *  retrieve fields for sobject
   *  @param sObjectName      Name of sobject
   *  @param isUpdateable     True to if fields must be updateable
   *  @param isCreateable     True to if fields must be creatable
   *  @return FieldWrapper[]  List of FieldWrapper objects
   */
  public static FieldWrapper[] retrieveFields(String sObjectName, Boolean isUpdateable, Boolean isCreatable) {

    FieldWrapper[] fwrappers = new FieldWrapper[0];

    String[] fieldsExclude = new String[] {
      'IsDeleted', 'CreatedDate', 'CreatedById', 'LastModifiedDate', 'LastModifiedById', 'OwnerId', 'SystemModstamp', 'LastViewedDate', 'LastReferencedDate'
    };

    String[] excludedTypes = new String[] {
      'DATACATEGORYGROUPREFERENCE', 'ADDRESS', 'ANYTYPE', 'JUNCTIONIDLIST', 'LOCATION', 'BASE64', 'ENCRYPTEDSTRING', 'COMBOBOX'
    };

    SObjectType sobjType = Schema.getGlobalDescribe().get(sObjectName);
    if(sobjType == null){
      return fwrappers;
    }
    Map<String, Schema.SObjectField> fieldMap = sobjType.getDescribe().fields.getMap();

    for(String fieldName : fieldMap.keySet()){
      if(fieldsExclude.contains(fieldName)){
        continue;
      }
      Schema.DescribeFieldResult field = fieldMap.get(fieldName).getDescribe();
      String fieldLabel = field.getLabel();
      String fieldType = String.valueOf(field.getType());

      if(excludedTypes.contains(fieldType) || (isCreatable && !field.isCreateable()) || !field.isAccessible() || (isUpdateable && !field.isUpdateable())){
        continue;
      }
      FieldWrapper fw = new FieldWrapper(field.getName(), fieldLabel, fieldType, field.getLength());
      fw.isUnique = field.isUnique();
      fw.isCaseSensitive = field.isCaseSensitive();      
      if(fieldType == 'PICKLIST' || fieldType == 'MULTIPICKLIST'){
        fw.setPickListValues(field.getPicklistValues());
      }
      fwrappers.add(fw);
    }
    return fwrappers;
  }

  public static Id createSharingGroup(){
    Group[] groups = [SELECT Id, DeveloperName, (SELECT Id, GroupId, UserOrGroupId FROM GroupMembers) FROM Group 
      WHERE DeveloperName =: PUBLIC_GROUP_DEVELOPER_NAME OR DeveloperName = 'AllInternalUsers'];

    Map<String, Group> groupMap = new Map<String, Group>();
    Id allInternalUsers; 

    for(Group grou : groups){
      groupMap.put(grou.DeveloperName, grou);  
    }
    allInternalUsers = groupMap.get('AllInternalUsers')?.Id;
    
    if(!groupMap.containsKey(PUBLIC_GROUP_DEVELOPER_NAME)){
      Group grou = new Group(Name=PUBLIC_GROUP_DEVELOPER_NAME, DeveloperName=PUBLIC_GROUP_DEVELOPER_NAME);
      insert grou;
      groupMap.put(PUBLIC_GROUP_DEVELOPER_NAME, grou);
    }
    Group grou = groupMap.get(PUBLIC_GROUP_DEVELOPER_NAME);
    Boolean isAlreadyShared = false;
    if(grou?.GroupMembers?.size() >= 1){
      for(GroupMember groupMembe : grou.GroupMembers){
        if(groupMembe.UserOrGroupId == allInternalUsers){
          isAlreadyShared = true;
          break;
        }
      }
    }
    if(!isAlreadyShared){
      GroupMember groupMembe = new GroupMember(GroupId=grou.Id, UserOrGroupId=allInternalUsers);
      insert groupMembe;
    }  
    return grou?.Id;  
  }

  @AuraEnabled
  public static Id createWorkspace(){

    ContentWorkspace[] cws = [SELECT Id FROM ContentWorkspace WHERE DeveloperName=: WORKSPACE_DEVELOPER_NAME];
    String workspaceName = WORKSPACE_DEVELOPER_NAME.replace('_', ' ');

    if(cws.size() == 0){
      cws.add(new ContentWorkspace(Name=workspaceName, DeveloperName=WORKSPACE_DEVELOPER_NAME));
      insert cws;
    }
    ContentWorkspacePermission[] cwsp = [SELECT Id FROM ContentWorkspacePermission WHERE Name = :workspaceName];    
    if(cwsp.size() == 0){
      cwsp.add(new ContentWorkspacePermission(Name=workspaceName, PermissionsAddComment=true, PermissionsAddContent=true, 
        PermissionsAddContentOBO=true, PermissionsArchiveContent=true, PermissionsChatterSharing=true, PermissionsDeleteContent=true, PermissionsDeliverContent=true, PermissionsFeatureContent=true,
        PermissionsManageWorkspace=true, PermissionsModifyComments=true, PermissionsOrganizeFileAndFolder=true, PermissionsTagContent=true, PermissionsViewComments=true
      ));
      insert cwsp;
    }
    Id groupId = createSharingGroup();
    ContentWorkspaceMember[] cwsm = [SELECT Id FROM ContentWorkspaceMember WHERE ContentWorkspaceId =: cws[0].Id AND MemberId =: groupId];
    if(cwsm.size() == 0){
      cwsm.add(new ContentWorkspaceMember(ContentWorkspaceId=cws[0].Id, ContentWorkspacePermissionId=cwsp[0].Id, MemberId=groupId));
      insert cwsm;
    }
    return cws[0].Id;
  }

  /**
   *  save mappings to file
   *  @param jsonObject  json string containing the field object datay
   */
  @AuraEnabled
  public static void saveJsonToFile(String jsonObject, String fileName){

    ContentVersion[] conts = Database.query('SELECT ContentDocumentId FROM ContentVersion WHERE Title =: fileName LIMIT 1');

    if(conts.size() > 0){
      delete new ContentDocument(Id = conts[0].ContentDocumentId);
    }
    ContentWorkspace[] cws = [SELECT Id FROM ContentWorkspace WHERE DeveloperName =: WORKSPACE_DEVELOPER_NAME];

    ContentVersion cont;
    cont = new ContentVersion();
    cont.Title = fileName;
    cont.PathOnClient = fileName + '.txt';
    cont.Origin = 'C';
    cont.SharingOption = 'A';
    cont.SharingPrivacy = 'N';    
    cont.VersionData = Blob.valueOf(jsonObject);
    cont.FirstPublishLocationId = cws[0].Id;
    insert cont;
  }


  /**
   *  retrieve settings for copy line items from clipboard feature
   *  @param   recordId              The associated opportunity or quote Id
   *  @param   randomKey             Pass a different numeric value each time to force Salesforce to refresh cache.
   *  @return  Map<String, Object>   Map containing settings and oppportunity record
   */
  @AuraEnabled(Cacheable=true)
  public static Map<String, Object> retrieveSettings(Id recordId, Decimal randomKey){

    Map<String, Object> resultMap = new Map<String, Object>();
    String sobjectName = String.valueOf(recordId.getSObjectType());
    Map<String, String> fileNameMap = new Map<String, String>{  MAPPINGS_FILENAME => 'mappings', SETTINGS_FILENAME => 'settings'};
    Map<String, String> labelfileNameMap = new Map<String, String>();

    for(String key : fileNameMap.keySet()){
      labelfileNameMap.put(fileNameMap.get(key), key);
    }
    ContentVersion[] conts = [SELECT Id, Title, VersionData FROM ContentVersion WHERE Title IN :fileNameMap.keySet()];
    Opportunity[] opportunities = new Opportunity[0];
    SObject[] quotes = new SObject[0];
    if(sobjectName == 'Opportunity'){
      opportunities = [SELECT Pricebook2Id FROM Opportunity WHERE Id =: recordId];
      resultMap.put('isOpportunity', true);
    }
    else if(sobjectName == 'Quote'){
      quotes = Database.query('SELECT Pricebook2Id FROM Quote WHERE Id =: recordId');
      resultMap.put('isQuote', true);
    }
    Opportunity opportunity;
    SObject quote;

    if(conts.size() > 0){
      for(ContentVersion cont : conts){
        String jsonObject = cont.versionData.toString();
        resultMap.put(fileNameMap.get(cont.Title), jsonObject);
      }
    }
    if(opportunities.size() > 0){
      opportunity = opportunities[0];
    }
    if(quotes.size() > 0){
      quote = quotes[0];
    }
    CopyLineItemsSetting__mdt[] copyLineItemsSettings = [SELECT SaveDeleteEmptyTables__c, SaveDeleteMappings__c, ProfileNames__c, AllowRowDeletion__c, 
      ShowProductPricebookEntryOptions__c FROM CopyLineItemsSetting__mdt];
    Profile userProfile = [SELECT Name FROM Profile WHERE Id =: userinfo.getProfileId()];

    resultMap.put('copyLineItemsSettings', copyLineItemsSettings);
    resultMap.put('userProfile', userProfile);
    resultMap.put('labelfileNameMap', labelfileNameMap);
    resultMap.put('opportunityLineItemFields', retrieveFields('OpportunityLineItem', false));
    resultMap.put('quoteLineItemFields', retrieveFields('QuoteLineItem', false));
    resultMap.put('product2Fields', retrieveFields('Product2', false));
    resultMap.put('opportunity', opportunity);
    resultMap.put('quote', quote);
    resultMap.put('hasPermission', featureCopyClipboardLineItems);
    return resultMap;
  }


  /**
   *  retrieve opportunity record and product fields
   *  @param   recordId              The associated record Id for opportunity or quote
   *  @return  Map<String, Object>   Map containing opportunity and product records
   */
  @AuraEnabled
  public static Map<String, Object> retrieveOpportunityQuoteAndProductData(Id recordId, Map<String, String[]> productFieldsMatchMap){

    String sobjectName = String.valueOf(recordId.getSObjectType());
    Opportunity oppty;
    SObject quote;
    String currencyCodeField = (UserInfo.isMulticurrencyOrganization() ? ', CurrencyIsoCode' : '');

    if(sobjectName == 'Opportunity'){
      oppty = Database.query('SELECT Pricebook2Id, EnablePricebook2Hierarchy__c' + currencyCodeField + ' FROM Opportunity WHERE Id =: recordId');
    }
    else if(sobjectName == 'Quote'){
      quote = Database.query('SELECT Pricebook2Id, Opportunity.EnablePricebook2Hierarchy__c' + currencyCodeField + ' FROM Quote WHERE Id =: recordId');
    }
    Pricebook2 standardPricebook = [SELECT Id FROM Pricebook2 WHERE IsStandard = true];

    String[] soqlFields = new String[] { 'Pricebook2Id' };
    String[] soqlWheres = new String[0];
    Set<String> fieldValues1 = new Set<String>(), fieldValues2 = new Set<String>(), fieldValues3 = new Set<String>();
    Integer i = 0;

    for(String field : productFieldsMatchMap.keySet()){

      soqlFields.add('Product2.' + field);
      String variableName = 'fieldValues1';
      String[] values = productFieldsMatchMap.get(field);
      if(i == 0){
        fieldValues1.addAll(values);
      }
      else if(i == 1){
        fieldValues2.addAll(values);
        variableName = 'fieldValues2';
      }
      else if(i >= 2){
        fieldValues3.addAll(values);
        variableName = 'fieldValues3';
      }
      soqlWheres.add('Product2.' + field + ' IN :' + variableName);
      i++;
    }
    if(i == 1){
      fieldValues1.remove('');
      fieldValues1.remove(null);
    }

    Id pricebook2Id;
    if(sobjectName == 'Opportunity'){
      pricebook2Id = oppty.EnablePricebook2Hierarchy__c ? standardPricebook.Id : oppty.Pricebook2Id;
    }
    else if(sobjectName == 'Quote'){
      pricebook2Id = (Boolean)quote.getSObject('Opportunity').get('EnablePricebook2Hierarchy__c') ? standardPricebook.Id : (Id)quote.get('Pricebook2Id');
    }
    pricebook2Id = pricebook2Id != null ? pricebook2Id : standardPricebook.Id;

    String queryString = 'SELECT ' + String.join(soqlFields, ', ') + ' FROM PricebookEntry WHERE Pricebook2Id = \'' + pricebook2Id + '\' AND (' + String.join(soqlWheres, ' AND ') + ')';
    if(UserInfo.isMulticurrencyOrganization()){
      String currencyIsoCode = '';
      if(sobjectName == 'Opportunity'){
        currencyIsoCode = (String)oppty.get('CurrencyIsoCode');
      }
      else if(sobjectName == 'Quote'){
        currencyIsoCode = (String)quote.get('CurrencyIsoCode');
      }
      queryString += ' AND CurrencyIsoCode = \'' + currencyIsoCode + '\'';
    }
    PricebookEntry[] pbeList = Database.query(queryString);

    Map<String, Object> resultMap = new Map<String, Object>();
    resultMap.put('pricebookEntries', pbeList);
    resultMap.put('standardPricebook2Id', standardPricebook.Id);
    if(oppty != null){
      resultMap.put('opportunityPricebook2Id', oppty.Pricebook2Id);
      resultMap.put('opportunity', oppty);
    }
    else if(quote != null){
      resultMap.put('quotePricebook2Id', quote.get('Pricebook2Id'));
      resultMap.put('quote', quote);
    }
    return resultMap;
  }

  /**
   *  retrieve settings for copy line items from clipboard feature
   *  @param newProducts        The products to insert.
   *  @param pricebook2Ids      The pricebooks to create the products in.
   *  @param product2Fields     The product fields to query after product creation.
   *  @param isCreatePricebookEntries Create pricebook entries if true.
   *  @param currencyIsoCode    The currency iso code.
   *  @return PricebookEntry[]   The pricebook entries of the objects created
   */
  @AuraEnabled
  public static PricebookEntry[] createNewProducts(Product2[] newProducts, Id[] pricebook2Ids, String[] product2Fields, Boolean isCreatePricebookEntries, String currencyIsoCode){
    Savepoint dbSavePoint = Database.setSavepoint();
    insert newProducts;

    PricebookEntry[] pbeList = new PricebookEntry[0];
    Set<Id> pricebook2IdSet = new Set<Id>();
    pricebook2IdSet.addAll(pricebook2Ids);
    String currencyIsoCodeClause = '';

    if(String.isNotBlank(currencyIsoCode) && UserInfo.isMulticurrencyOrganization()){
      currencyIsoCodeClause = ' AND CurrencyIsoCode = \'' + currencyIsoCode + '\'';
    }
    if(isCreatePricebookEntries){
      PricebookEntry[] pbesExisting = Database.query('SELECT Product2Id, Pricebook2Id FROM PricebookEntry WHERE Pricebook2Id IN :pricebook2IdSet AND Product2Id IN :newProducts' + currencyIsoCodeClause);
      Set<String> pricebookProductKeys = new Set<String>();
      for(PricebookEntry pbe : pbesExisting){
        pricebookProductKeys.add('' + pbe.Pricebook2Id + pbe.Product2Id);
      }
      for(Product2 newProduct : newProducts){
        for(Id pricebook2Id : pricebook2IdSet){
          // Do not insert pricebook entries that already exist
          if(pricebookProductKeys.contains('' + newProduct.Id + pricebook2Id)){
            continue;
          }
          PricebookEntry pbe = new PricebookEntry(Product2Id=newProduct.Id, Pricebook2Id=pricebook2Id, UnitPrice=0, IsActive=true);
          if(String.isNotBlank(currencyIsoCode)){
            pbe.put('CurrencyIsoCode', currencyIsoCode);
          }
          pbeList.add(pbe);
        }
      }
      insert pbeList;
    }
    Set<String> product2FieldSet = new Set<String>();
    for(String product2Field : product2Fields){
      product2FieldSet.add('Product2.' + product2Field);
    }
    product2FieldSet.add('Pricebook2Id');
    String[] product2FieldList = new List<String>(product2FieldSet);
    PricebookEntry[] pbes = Database.query('SELECT ' + String.join(product2FieldList, ', ') + ' FROM PricebookEntry WHERE Pricebook2Id IN :pricebook2IdSet AND Product2Id IN :newProducts' + currencyIsoCodeClause);
    if(pbes.size() < newProducts.size()){
      Database.rollback(dbSavePoint);
    }
    return pbes;
  }

  /**
   *  Upsert opportunity or quote line items. Line items are assumed to share the same parent record.
   *  @param  records       The opportunity or quote line items to insert.
   *  @param  orderIndexes  Integer list specifying order of corresponding opportunity or quote line items.
   *  @return SObject       The inserted opportunity or quote line items.
   */
  @AuraEnabled
  public static SObject[] upsertOpportunityQuoteLineItems(SObject[] records, Integer[] orderIndexes){
         
    if(records.size() > 0){
      String typeName = records[0].getSObjectType().getDescribe().getName();
      String query;
      Id parentId;

      if(typeName == 'QuoteLineItem'){
        parentId = (Id)records[0].get('QuoteId');
        query = 'SELECT Id, SortOrder FROM QuoteLineItem WHERE QuoteId =: parentId ORDER BY SortOrder';
      }
      else if(typeName == 'OpportunityLineItem'){
        parentId = (Id)records[0].get('OpportunityId');
        query = 'SELECT Id, SortOrder FROM OpportunityLineItem WHERE OpportunityId =: parentId ORDER BY SortOrder';        
      }
      SObject[] existingLineItems = Database.query(query);
      upsert records; 

      Integer existingCount = existingLineItems.size();
      Integer lastSortIndex = 0;
      if(existingCount > 0){
        lastSortIndex = (Integer)existingLineItems[existingCount - 1].get('SortOrder');
        lastSortIndex = lastSortIndex != null ? lastSortIndex : 0;
      }
      for(Integer i = 0; i < records.size(); i++){
        records[i].put('SortOrder', orderIndexes[i] + lastSortIndex);
      }
      TriggerHelper.disableKineticGrowthTriggers();
      update records;
      TriggerHelper.enableKineticGrowthTriggers();
    }
    return records;
  }
}