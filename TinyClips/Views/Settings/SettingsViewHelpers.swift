import Foundation
import SwiftUI
import AppKit

extension Binding where Value == Int {
	var doubleValue: Binding<Double> {
		Binding<Double>(
			get: { Double(wrappedValue) },
			set: { wrappedValue = Int($0) }
		)
	}
}
