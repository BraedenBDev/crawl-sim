#!/usr/bin/env bash
# schema-fields.sh — Required field definitions per schema.org type.
# Source this file, then call required_fields_for <SchemaType>.

required_fields_for() {
  case "$1" in
    Organization)        echo "name url" ;;
    WebSite)             echo "name url" ;;
    Article)             echo "headline author datePublished" ;;
    NewsArticle)         echo "headline author datePublished" ;;
    FAQPage)             echo "mainEntity" ;;
    BreadcrumbList)      echo "itemListElement" ;;
    CollectionPage)      echo "name" ;;
    ItemList)            echo "itemListElement" ;;
    AboutPage)           echo "name" ;;
    ContactPage)         echo "name" ;;
    Product)             echo "name" ;;
    LocalBusiness)       echo "name address" ;;
    ProfessionalService) echo "name" ;;
    Person)              echo "name" ;;
    ImageObject)         echo "contentUrl" ;;
    PostalAddress)       echo "streetAddress" ;;
    *)                   echo "" ;;
  esac
}
