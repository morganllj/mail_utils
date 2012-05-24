import urllib2
# try to import the ElementTree API included with py 2.5 first
# otherwise fallback on third-party install (prereq)
try:
    from xml.etree import ElementTree
except:
    from elementtree import ElementTree

# load mailman config
try:
    from Mailman import mm_cfg
except:
    print "WARNING: Cannot find mailman config"

MAILMAN_LIST_ACCOUNTS = ('',
                         '-admin', '-bounces', '-confirm', '-join', '-leave',
                         '-owner', '-request', '-subscribe', '-unsubscribe')
ZIMBRA_SOAP_HEADERS = {
    'Content-type': 'text/xml; charset=utf-8',
}

ZIMBRA_AUTH_REQUEST = \
    '<soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope">' \
    '  <soap:Body>'                                                        \
    '    <AuthRequest xmlns="urn:zimbraAdmin">'                            \
    '      <name>%s</name>'                                                \
    '      <password>%s</password>'                                        \
    '    </AuthRequest>'                                                   \
    '  </soap:Body>'                                                       \
    '</soap:Envelope>'

ZIMBRA_REQUEST = \
    '<soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope">' \
    '  <soap:Header>'                                                      \
    '    <context xmlns="urn:zimbra">'                                     \
    '      <authToken>%s</authToken>'                                      \
    '      <sessionId id="%s" type="admin">%s</sessionId>'                 \
    '    </context>'                                                       \
    '  </soap:Header>'                                                     \
    '  <soap:Body>%s</soap:Body>'                                          \
    '</soap:Envelope>'
# ZIMBRA_CREATE_REQUEST = \
#     '<CreateAccountRequest xmlns="urn:zimbraAdmin">' \
#     '  <name>%s</name>'                              \
#     '  <a n="zimbraMailTransport">smtp:%s</a>'       \
#     '</CreateAccountRequest>'

ZIMBRA_CREATE_REQUEST = \
    '<CreateDistributionListRequest xmlns="urn:zimbraAdmin">' \
    '  <name>%s</name>'                              \
    '  <a n="zimbraHideInGal">TRUE</a>'       \
    '  <a n="zimbraMailForwardingAddress">%s</a>'       \
    '</CreateDistributionListRequest>'

ZIMBRA_GET_REQUEST = \
    '<GetDistributionListRequest xmlns="urn:zimbraAdmin">' \
    '  <dl by="name">%s</dl>'           \
    '</GetDistributionListRequest>'

ZIMBRA_DELETE_REQUEST = \
    '<DeleteDistributionListRequest xmlns="urn:zimbraAdmin">' \
    '  <id>%s</id>'                                  \
    '</DeleteDistributionListRequest>'

class ZimbraIntegration:
    def __init__(self):
        self.__authToken = None
        self.__sessionId = None
        try:
            self.__url       = mm_cfg.ZIMBRA_ADMIN_SOAP_SERVICE
            self.__transport = mm_cfg.MAILMAN_SMTP_TRANSPORT
            self.__username  = mm_cfg.ZIMBRA_ADMIN_USERNAME
            self.__password  = mm_cfg.ZIMBRA_ADMIN_PASSWORD
            self.__listhost  = mm_cfg.DEFAULT_URL_HOST
        except: # testing configuration
            self.__url = "https://192.168.230.130:7071/service/admin/soap/"
            self.__transport = 'rhel5-testn.testdomain.com'
            self.__username  = 'admin@testdomain.com'
            self.__password  = 'password'

    def __envelope(self, request):
        if self.__authToken is None:
            self.__getAuthToken()

        envelope = ZIMBRA_REQUEST % (self.__authToken, self.__sessionId,
               self.__sessionId, request)
        return envelope

    def __sendRequest(self, request):
        req = urllib2.Request(self.__url, request, ZIMBRA_SOAP_HEADERS)
        try:
            resp = urllib2.urlopen(req)
            tree = ElementTree.parse(resp)
        except urllib2.HTTPError, e:
            tree = ElementTree.parse(e.fp)
            error = tree.findtext(
                    "//{http://www.w3.org/2003/05/soap-envelope}Text")
            raise ZimbraIntegrationException(error)
        return tree

    def __getAuthToken(self):
        requestBody = ZIMBRA_AUTH_REQUEST % (self.__username, self.__password)
        tree = self.__sendRequest(requestBody)
        self.__authToken = tree.findtext("//{urn:zimbraAdmin}authToken")
        self.__sessionId = tree.findtext("//{urn:zimbraAdmin}sessionId")

    def __checkAccounts(self, name, domain):
        found = False
        for i in MAILMAN_LIST_ACCOUNTS:
            address = "%s%s@%s" % (name, i, domain)
            try:
                self.getAccount(address)
                found = True
            except:
                pass
            if found is True: # can't just immediately raise above
                raise ZimbraIntegrationException(
                        "accounts already exist for: " + name)

    def createAccounts(self, name, domain):
        self.__checkAccounts(name, domain)

        try:
            for i in MAILMAN_LIST_ACCOUNTS:
                address = "%s%s@%s" % (name, i, domain)
                list = "%s%s" % (name, i)
                self.createAccount(list, address)
        except ZimbraIntegrationException, e:
            self.__rollbackCreation(name, domain)
            raise ZimbraIntegrationException(e.reason)

    def __rollbackCreation(self, name, domain):
        self.deleteAccounts(name, domain)

    def getAccount(self, name):
        requestBody = ZIMBRA_GET_REQUEST % name
        requestBody = self.__envelope(requestBody)
        tree = self.__sendRequest(requestBody)
        node = tree.find("//{urn:zimbraAdmin}dl")
        return node.get("id")

    def deleteAccounts(self, name, domain):
        for i in MAILMAN_LIST_ACCOUNTS:
            try:
                address = "%s%s@%s" % (name, i, domain)
                id = self.getAccount(address)
                self.deleteAccount(id)
            except:
                pass

    def deleteAccount(self, id):
        requestBody = self.__envelope(ZIMBRA_DELETE_REQUEST % id)
        self.__sendRequest(requestBody)

    def createAccount(self, name, address):
        forwardingaddr = "%s@%s" % (name, self.__listhost)
        requestBody = ZIMBRA_CREATE_REQUEST % (address, forwardingaddr)
        requestBody = self.__envelope(requestBody)
        self.__sendRequest(requestBody)
        id = self.getAccount(address)

class ZimbraIntegrationException(Exception):
    def __init__(self, reason):
        self.reason = reason
    def __str__(self):
        return self.reason
